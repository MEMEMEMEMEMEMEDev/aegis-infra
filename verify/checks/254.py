"""Check 254 — a call the job declares harmless says nothing the retry reads as the network.

MEASURED 2026-09-23 on the cloud instance (plan/18 §5, finding 13):
base-images failed for a real reason, and phase 80 re-fired it at once
as «a transient network failure». The signature it matched was
`curl: (6) Could not resolve host: vlogs-events…`: the best-effort event
the job sends to a collector that phase 85 installs AFTER phase 80. The
job itself says that call does not matter (`|| echo 'NOTICE: … the build
does NOT fail for this'`), and its stderr in the console turned a real
failure into a retry — the retry that, before finding 14 was fixed, was
the only thing giving php its second pass.

The class: a command whose failure the pipeline declares harmless.
Its stderr stays out of the console (the notice carries curl's exit code,
which is the diagnosis without the words), and the notice's own text
does not match AEGIS_NET_SIGS. Read from every Jenkinsfile the seed
ships, code only.

WHAT DECLARES A CALL HARMLESS IS THE ACTION, NOT THE WORD. Until
2026-09-30 this check looked for `|| echo 'NOTICE: …'`. mirror-images
said the same thing with `WARNING:` and the check never saw it; that day,
on alpha-arch, its two curls printed «Could not resolve host» and a scan
that had found CVEs was re-fired twice as a network failure. A fallback
that echoes a SENTENCE (three words or more, whatever the first one is)
is the pipeline swallowing a failure; one that echoes a value
(`|| echo 0`, `|| echo ""`) is a default, and stays out of scope.
"""
import os
import re
import sys

ROOT = sys.argv[1]
SEED = os.path.join(ROOT, "seed", "platform")
COMMON = os.path.join(ROOT, "lib", "common.sh")

with open(COMMON, encoding="utf-8") as f:
    m = re.search(r"^AEGIS_NET_SIGS='([^']*)'", f.read(), re.M)
if not m:
    print("SCOPE: lib/common.sh defines no AEGIS_NET_SIGS — nothing to compare the notices against")
    sys.exit(0)
SIGS = re.compile(m.group(1), re.I)

NOTICE = re.compile(r"""\|\|\s*echo\s+(['"])(\S+(?:\s+\S+){2,}.*?)\1\s*$""")
pipelines = []
for dp, dn, fn in os.walk(SEED):
    for f in fn:
        if f.startswith("Jenkinsfile"):
            pipelines.append(os.path.join(dp, f))

calls = 0
for p in sorted(pipelines):
    rel = os.path.relpath(p, ROOT)
    with open(p, encoding="utf-8") as f:
        lines = f.read().split("\n")
    for i, ln in enumerate(lines):
        if re.match(r"^\s*(//|#)", ln):
            continue
        n = NOTICE.search(ln)
        if not n:
            continue
        calls += 1
        # the logical command: back while the line above continues into this one
        j = i
        while j > 0 and lines[j - 1].rstrip().endswith("\\"):
            j -= 1
        cmd = "\n".join(lines[j:i + 1])
        cmd = cmd[:cmd.rindex("||")]
        if "2>/dev/null" not in cmd:
            print(f"{rel}:{i + 1}: the call before this notice writes its stderr to the console "
                  f"— a curl error there is read as a network failure and a real failure is retried")
        if SIGS.search(n.group(2)):
            print(f"{rel}:{i + 1}: the notice itself matches AEGIS_NET_SIGS («{SIGS.search(n.group(2)).group(0)}»)")

print(f"SCOPE: {calls} call(s) declared harmless in {len(pipelines)} pipeline(s) the seed ships")
