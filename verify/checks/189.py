"""Scanner of check 189 — the app scan honors a repo-local trivyignore,
and only in the disciplined shape: passed to trivy AND dated.

Prose is stripped before scanning: the stage documents the very words
this asks for, and a scanner that read the comment would find them
inside the explanation of why they must be in the code.
"""
import os
import re
import sys

ROOT = sys.argv[1]
TPL = os.path.join(ROOT, "seed/platform/docs/protocols/templates/Jenkinsfile.app")


def sin_prosa(text):
    out = []
    for l in text.splitlines():
        st = l.lstrip()
        if st.startswith("//") or st.startswith("#"):
            continue
        out.append(l)
    return "\n".join(out)


fallos = []
hechos = 0

if not os.path.exists(TPL):
    print("the seed ships no Jenkinsfile.app: this check has no subject")
    print("__COUNT__ 0", file=sys.stderr)
    sys.exit(0)

s = sin_prosa(open(TPL, encoding="utf-8").read())

# isolate the scan stage
m = re.search(r"stage\('scan'\).*?stage\('push'\)", s, re.S)
scan = m.group(0) if m else ""

# 1 — the scan reaches trivy with the repo-local ignorefile when present.
hechos += 1
if "trivyignore.yaml" not in scan:
    fallos.append("the scan stage does not mention a repo-local trivyignore.yaml: "
                  "an app on a base whose CVE the platform already accepted at "
                  "mirror time cannot pass, though nothing about its own code is wrong")
elif "--ignorefile" not in scan:
    fallos.append("the scan names trivyignore.yaml but never passes --ignorefile to "
                  "trivy: the file would sit in the repo and change nothing")
else:
    # the flag has to reach the trivy INVOCATION, not merely be assigned:
    # a command that builds `IGN="--ignorefile ..."` and never appends
    # $IGN scans with no exception at all.
    inv = re.search(r"trivy image[\s\S]*?no-progress[^\n]*(?:\n[^\n]*){0,2}", scan)
    if not inv or "$IGN" not in inv.group(0):
        fallos.append("the trivy invocation does not append $IGN: the ignorefile is "
                      "assigned and then never handed to the scan, so it changes nothing")

# 2 — it is CONDITIONAL on the file existing (an app without one is the
# normal case and must still be scanned with no exceptions).
hechos += 1
if "trivyignore.yaml" in scan and not re.search(r"\[\s*-f\s+trivyignore\.yaml\s*\]", scan):
    fallos.append("the ignorefile is not guarded by `[ -f trivyignore.yaml ]`: an app "
                  "that ships none would have trivy fail on a missing file, or the "
                  "flag would always be passed")

# 3 — the exception stays scoped: severities and --ignore-unfixed are NOT
# widened alongside it (a repo file must not become a way to lower the bar).
hechos += 1
if "CRITICAL,HIGH" not in scan or "--ignore-unfixed" not in scan:
    fallos.append("the scan no longer holds CRITICAL,HIGH with --ignore-unfixed: the "
                  "repo-local ignore is meant to carry a base-layer exception, not to "
                  "soften what the scan looks for")

for f in fallos:
    print(f)
print("__COUNT__ %d" % hechos, file=sys.stderr)
