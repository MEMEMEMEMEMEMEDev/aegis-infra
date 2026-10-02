"""Check 276 — the round reads each multibranch job inside its own block.

FOUND on alpha-debian, 2026-10-02: with AI=no, the job-dsl carries
`multibranchPipelineJob('ai-gateway-mb')` with `repository('')`. The
round's «every push built» read the jobs with ONE regex — the job's name,
`.*?`, then a non-empty repo — so it stretched past the empty repo to the
NEXT job's: ai-gateway-mb was judged against the portfolio's repo («no
build at all»), and portafolio-app-mb itself was never looked at. Every
instance without AI turns red the day it gets its first app.

This sidecar RUNS that block of libexec/aegis-check (the heredoc, as it
is) over a fixture values.yaml with three jobs — the canary, the AI job
with an empty repo IN THE MIDDLE, the portfolio — with a `gh` and a
`kubectl` that answer like GitHub and Jenkins: every repo's HEAD built.
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
CHECK = os.path.join(ROOT, "libexec", "aegis-check")
findings = []
src = open(CHECK, encoding="utf-8").read()
m = re.search(r'heading "every push built"\npush_output=\$\(AEGIS_PLATFORM="\$PLATFORM_DIR" \\\n\s*GRACE="[^"]*" python3 - <<\'PYEOF\'\n(.*?)\nPYEOF\n', src, re.S)
if not m:
    print("the «every push built» block of aegis-check could not be found: re-aim this check")
    sys.exit(0)
block = m.group(1)

SHA = "a" * 40
VALUES = """controller:
  JCasC:
    configScripts:
      aegis-jobs: |
        jobs:
          - script: >
              multibranchPipelineJob('hello-aegis-mb') {
                branchSources {
                  github {
                    repoOwner('Own')
                    repository('aegis-canary')
                  }
                }
              }
          - script: >
                multibranchPipelineJob('ai-gateway-mb') {
                  branchSources {
                    github {
                      repoOwner('Own')
                      repository('')
                    }
                  }
                }
          - script: >
              multibranchPipelineJob('portafolio-app-mb') {
                branchSources {
                  github {
                    repoOwner('Own')
                    repository('portafolio-app')
                  }
                }
              }
"""
with tempfile.TemporaryDirectory() as tmp:
    vdir = os.path.join(tmp, "platform", "k8s", "base", "platform", "jenkins")
    os.makedirs(vdir)
    open(os.path.join(vdir, "values.yaml"), "w").write(VALUES)
    bindir = os.path.join(tmp, "bin")
    os.makedirs(bindir)
    open(os.path.join(bindir, "gh"), "w").write(
        "#!/bin/sh\ncase \"$*\" in\n"
        "  *repos/Own/aegis-canary/commits/main*|*repos/Own/portafolio-app/commits/main*) "
        f"echo '{SHA} 2026-01-01T00:00:00Z' ;;\n"
        "  *) exit 1 ;;\nesac\n")
    open(os.path.join(bindir, "kubectl"), "w").write(
        "#!/bin/sh\nfor a in \"$@\"; do last=\"$a\"; done\n"
        "case \"$last\" in\n"
        "  *jobs/hello-aegis-mb/*|*jobs/portafolio-app-mb/*)\n"
        "    case \"$last\" in ls*) echo 3 ;; *Checking*) echo " + SHA + " ;; esac ;;\n"
        "  *) : ;;\nesac\n")
    for f in ("gh", "kubectl"):
        os.chmod(os.path.join(bindir, f), 0o755)
    env = {"PATH": bindir + os.pathsep + os.environ["PATH"], "AEGIS_PLATFORM": os.path.join(tmp, "platform"), "GRACE": "15"}
    p = subprocess.run([sys.executable, "-c", block], capture_output=True, text=True, env=env, timeout=60)
    out = p.stdout
    if "BAD:" in out:
        findings.append("the round reports a failure where every repo's HEAD is built: "
                        + "; ".join(l for l in out.splitlines() if l.startswith("BAD:")))
    if "NOTE: portafolio-app-mb #3" not in out:
        findings.append("the job declared after an empty-repo job is never looked at (portafolio-app-mb missing from the round)")
    if "NOTE: hello-aegis-mb #3" not in out:
        findings.append("the first job is not looked at")
    if not re.search(r"NOTE: ai-gateway-mb names no repository", out):
        findings.append("a job with no repository is not said: it disappears instead of being reported as switched off")
    if "GOOD: the 2 repos with a job" not in out:
        findings.append(f"the section's verdict is not «the 2 repos … built» (got {out.splitlines()[-1:] or p.stderr[-160:]})")

for x in findings:
    print(x)
print("SCOPE: the round's «every push built» block run over a values.yaml of 3 jobs (an empty repo in the middle) with a gh and a kubectl that answer every HEAD built")
