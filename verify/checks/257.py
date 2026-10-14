"""Check 257 — the mirror's door judges what comes in, and a retained image is not a broken install.

MEASURED 2026-09-30 on the Arch lab VM: phase 80 died because mirror-images
went red on python:3.12-slim and nodejs-distroless:22 — two OpenSSL CVEs
published the day before, fixed in Debian, not yet in the upstream images.
The platform runs neither. And the job re-judged every entry on every run,
so an image that entered clean last month could turn the install red today.

What the door does since then (plan/21, stage 4), and what this check holds:

1. mirror-images scans once to JSON and hands the findings to
   vuln-policy/verdict.sh (no `--exit-code 1` deciding on its own); verdict
   rc 1 is RETAINED (exit 10: named, not pushed), any other non-zero is
   BROKEN — an unjudged scan is never clean.
2. An entry already signed by aegis FROM THE SAME SOURCE is not judged
   again: `cosign verify -a aegis.dev/source=${SRC}` before the pull, and
   `cosign sign -a aegis.dev/source=${SRC}` leaves exactly that annotation.
3. The run ends red when something BROKE, UNSTABLE when entries were only
   retained, and prints one `RETAINED <image>` line per retained entry.
4. lib/jenkins.sh reads UNSTABLE as rc 4 and does not re-fire it.
5. Phase 80's door stops only when the PLATFORM needs a retained image
   (its k8s/ names it) — RUN here with a simulated Jenkins, five cases.
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
JF = os.path.join(ROOT, "seed", "platform", "mirror-images", "Jenkinsfile")
P80 = os.path.join(ROOT, "init", "phases", "80-supply-chain.sh")
JLIB = os.path.join(ROOT, "lib", "jenkins.sh")
findings = []


def code(path, comment):
    with open(path, encoding="utf-8") as f:
        return "\n".join(ln for ln in f.read().splitlines() if not re.match(rf"^\s*{comment}", ln))


jf = code(JF, "//")
mirror = re.search(r"stage\('mirror'\)\s*\{(.*)", jf, re.S)
body = mirror.group(1) if mirror else ""
if not body:
    findings.append("mirror-images has no stage('mirror')")

# ── 1. the scan hands its findings to the one verdict ──────────────────
scan = re.search(r"judged\s*=\s*sh\(returnStatus:\s*true,\s*script:\s*'''(.*?)'''", body, re.S)
if not scan:
    findings.append("the mirror's scan is not a `judged = sh(returnStatus: true, …)`: the stage cannot tell retained from broken")
else:
    sc = scan.group(1)
    if re.search(r"trivy image\b[^\n]*(?:\\\n[^\n]*)*--exit-code\s+1", sc):
        findings.append("the mirror's trivy decides on its own (`--exit-code 1`): the verdict never gets a say — the install of 2026-09-30 again")
    if "--format json" not in sc or not re.search(r"trivy convert --format template --template \"\$\(sh \"\$VP/verdict\.sh\" --template\)\"", sc):
        findings.append("the findings the verdict reads do not come from the same scan, through verdict.sh's own template")
    if not re.search(r"sh \"\$VP/verdict\.sh\" findings\.txt", sc):
        findings.append("the mirror never runs verdict.sh on the findings")
    case = re.search(r"case \"\$rc\" in(.*?)esac", sc, re.S)
    if not case or not re.search(r"^\s*1\)\s*exit 10\s*;;", case.group(1), re.M) \
            or not re.search(r"^\s*\*\)[^\n]*exit 1\s*;;", case.group(1), re.M):
        findings.append("the verdict's rc is not mapped as 1 → retained (exit 10), anything else → broken: an unjudged scan could pass")
    if "--ignorefile" not in sc:
        findings.append("the mirror's scan no longer reads trivyignore.yaml: every dated exception stops working")
push = body.find('echo "-- push')
ret = re.search(r"if \(judged == 10\) \{(.*?)\n\s*\}", body, re.S)
if not ret or "RETAINED << e.dst" not in ret.group(1) or not re.search(r"^\s*return\s*$", ret.group(1), re.M):
    findings.append("a retained entry is not recorded in RETAINED and left before the push")
elif push == -1 or ret.start() > push:
    findings.append("the retained branch comes after the push: a stopped image would be in the registry")
if not re.search(r"if \(judged != 0\) \{\s*error ", body):
    findings.append("a scan that could not be judged does not end the entry as broken")

# ── 2. provenance: what came in from this source is not judged again ───
ver = re.search(r"cosign verify[^']*?-a \"aegis\.dev/source=\$\{SRC\}\"", body, re.S)
sign = re.search(r"cosign sign[^']*?-a \"aegis\.dev/source=\$\{SRC\}\"", body, re.S)
if not ver:
    findings.append("no `cosign verify -a aegis.dev/source=${SRC}` before judging: every entry is judged again on every run")
if not sign:
    findings.append("`cosign sign` does not leave `aegis.dev/source=${SRC}`: the next run can never recognise what came in")
pull = body.find('echo "-- pull')
if ver and pull != -1 and ver.start() > pull:
    findings.append("the provenance check runs after the pull: nothing is saved and the entry is still judged")
if not re.search(r"if \(provenance == 0\) \{[^\n]*\n(?:[^\n]*\n)*?\s*return\s*\n\s*\}", body):
    findings.append("a verified provenance does not skip the entry")

# ── 3. how the run ends ────────────────────────────────────────────────
if not re.search(r"if \(RETAINED\) \{.*?RETAINED\.each \{ echo \"RETAINED \$\{it\}\" \}.*?unstable ", body, re.S):
    findings.append("a run with only retained entries does not end UNSTABLE naming each one (`RETAINED <image>`)")
if not re.search(r"if \(failed\) \{\s*error ", body):
    findings.append("a run with a broken entry does not end red")

# ── 4. lib/jenkins.sh ──────────────────────────────────────────────────
jl = code(JLIB, "#")
if not re.search(r"UNSTABLE\)\s*\n(?:.*\n){0,6}?\s*return 4 ;;", jl):
    findings.append("jenkins_wait_build does not answer UNSTABLE with its own rc 4")
br = re.search(r"jenkins_build_retry\(\)\s*\{(.*?)\n\}", jl, re.S)
if not br or not re.search(r"\(\(\s*wrc == 4\s*\)\).*?return 4", br.group(1), re.S) \
        or br.group(1).find("wrc == 4") > br.group(1).find("AEGIS_NET_SIGS"):
    findings.append("jenkins_build_retry does not hand UNSTABLE back (rc 4) before it looks for network signatures: a retained image would be re-fired")

# ── 5. phase 80's door, RUN with a simulated Jenkins ───────────────────
with open(P80, encoding="utf-8") as f:
    p80 = f.read()
fn = re.search(r"^_mirror_door\(\) \{\n.*?^\}\n", p80, re.S | re.M)
if not fn:
    findings.append("phase 80 has no _mirror_door: an UNSTABLE mirror is a dead install again")
elif not re.search(r'gate_diag "mirror-images-build-verde"(?:.|\n)*?\n\s*_mirror_door\s*$', p80, re.M):
    findings.append("the mirror-images-build-verde gate does not run _mirror_door")
else:
    harness = r'''
set -euo pipefail
log_warn() { echo "WARN $*" >&2; }; log_error() { echo "ERROR $*" >&2; }
jenkins_build_retry() { JENKINS_LAST_BUILD=7; return "$STUB_RC"; }
jenkins_get() { cat "$STUB_CONSOLE"; }
''' + fn.group(0) + r'''
rc=0; _mirror_door || rc=$?; echo "rc=$rc"
'''
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "k8s", "base"))
        with open(os.path.join(tmp, "k8s", "base", "bundle.yaml"), "w") as f:
            f.write("image: registry.registry-system.svc.cluster.local:5000/garage:v2.3.0@sha256:" + "a" * 64 + "\n")
        hp = os.path.join(tmp, "h.sh")
        with open(hp, "w") as f:
            f.write(harness)

        def door(rc, console):
            cp = os.path.join(tmp, "console.txt")
            with open(cp, "w") as f:
                f.write(console)
            p = subprocess.run(["bash", hp], capture_output=True, text=True, timeout=30,
                               env={"PATH": os.environ["PATH"], "STUB_RC": str(rc),
                                    "STUB_CONSOLE": cp, "PLATFORM_DIR": tmp})
            m = re.search(r"rc=(\d+)", p.stdout)
            return (int(m.group(1)) if m else -1), p.stderr

        cases = [
            ("the mirror is green", 0, "", 0),
            ("the mirror broke", 1, "FAILED x: boom\n", 1),
            ("retained, and the platform does not run it (2026-09-30)", 4,
             "RETAINED python:3.12-slim\nRETAINED nodejs-distroless:22\n", 0),
            ("retained, and the platform runs it", 4, "RETAINED garage:v2.3.0\n", 1),
            ("UNSTABLE naming nothing", 4, "Finished: UNSTABLE\n", 1),
        ]
        for label, rc, console, want in cases:
            got, err = door(rc, console)
            if got != want:
                findings.append(f"phase 80's door, {label}: rc {got}, expected {want} ({err.strip()[-140:]})")

print("SCOPE: mirror-images' scan, provenance and ending read as code; lib/jenkins.sh's UNSTABLE; "
      "phase 80's door run with a simulated Jenkins on 5 cases")
for x in findings:
    print(x)
