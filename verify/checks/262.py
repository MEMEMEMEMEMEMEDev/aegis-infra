"""Check 262 — a tenant build is judged on its own layers; the base's findings are the platform's.

MEASURED 2026-09-30 on the Arch lab VM, deploying an Astro portfolio from the
static template: build 1 compiled, built, and died at the scan on three
OpenSSL CVEs of nodejs-distroless:22 — the base, not the portfolio. The
platform had judged all three at the mirror's door (one excused with its
measurement, two admitted as dated debt) and image-watch re-scans them
every morning; the tenant could do nothing about them. On a user's instance
the same class cost half an hour of trivyignore path forms (their H-09).

Since then (plan/21, stage 5) the tenant scan:
- reads its bases' layers (`crane config` of every FROM the from-guard
  read, parsed by `verdict.sh --diff-ids` — build 3 found 0 layers because
  distroless ships its config indented, and a one-line reading saw none);
- splits the findings BY LAYER: the base's are AEGIS_INHERITED, printed
  and never this build's verdict; the image's own go to verdict.sh,
  against what RUNS today when it can be pulled (a new admission if not);
- refuses to judge without the platform's policy mounted (rc 3, never
  clean), and does not decide on its own (no --exit-code 1).

Build 4 of the same portfolio: 22 base layers, 3 findings inherited, 0 own,
SUCCESS, served at its public URL. This check reads the pipeline and RUNS
the two pieces that decide it: --diff-ids on real config shapes, and the
split, extracted from the Jenkinsfile as the build runs it.
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
JF = os.path.join(ROOT, "seed", "platform", "docs", "protocols", "templates", "Jenkinsfile.app")
VERDICT = os.path.join(ROOT, "seed", "platform", "k8s", "base", "platform", "vuln-policy", "verdict.sh")
findings = []

with open(JF, encoding="utf-8") as f:
    raw = f.read()
jf = "\n".join(l for l in raw.splitlines() if not l.lstrip().startswith("//"))
scan = re.search(r"stage\('scan'\)\s*\{(.*?)\n    stage\('push'\)", jf, re.S)
body = scan.group(1) if scan else ""
if not body:
    findings.append("Jenkinsfile.app has no stage('scan') before stage('push')")

# ── the pod carries the policy ─────────────────────────────────────────
trivy = re.search(r"- name: trivy\n(.*?)\n  - name: ", raw, re.S)
if not trivy or not re.search(r"- name: vuln-policy\s*\n\s*mountPath: /vuln-policy", trivy.group(1)):
    findings.append("the trivy container does not mount the platform's policy at /vuln-policy")
if not re.search(r"- name: vuln-policy\s*\n\s*configMap:\s*\n\s*name: aegis-vuln-policy\s*\n\s*optional: true", raw):
    findings.append("the pod has no optional volume from ConfigMap aegis-vuln-policy (without optional the pod waits in ContainerCreating, saying nothing)")

# ── the scan hands its findings to the verdict, split by layer ─────────
if re.search(r"trivy image\b[^\n]*(?:\\\n[^\n]*)*--exit-code\s+1", body):
    findings.append("the tenant's trivy decides on its own (`--exit-code 1`): the base's findings stop the app again")
if not re.search(r'crane config "\$ref" > "base-config-\$n\.json"', body):
    findings.append("the scan does not read every base's config (crane config of each FROM the from-guard read)")
if not re.search(r'sh "\$VP/verdict\.sh" --diff-ids < "\$c" >> base-diffids', body):
    findings.append("the base's layers are not read through `verdict.sh --diff-ids` (the one reader that takes any config shape)")
if not re.search(r'sh "\$VP/verdict\.sh" own\.txt running\.txt', body):
    findings.append("the image's own layers are not judged against what runs today when it could be pulled")
if not re.search(r'if \[ ! -f "\$VP/verdict\.sh" \] \|\| \[ ! -f "\$VP/policy\.yaml" \]; then\s*\n[^\n]*\n\s*exit 3', body):
    findings.append("with no policy mounted the scan does not stop as unjudged (exit 3)")
case = re.search(r'case "\$rc" in(.*?)esac', body, re.S)
if not case or not re.search(r"^\s*1\)[^\n]*exit 10\s*;;", case.group(1), re.M) or not re.search(r"^\s*\*\)[^\n]*exit 3\s*;;", case.group(1), re.M):
    findings.append("the verdict's rc is not mapped as 1 → stop (10), anything else → unjudged (3)")
if not re.search(r"if \(judged == 10\) \{\s*error ", body) or not re.search(r"if \(judged != 0\) \{\s*error ", body):
    findings.append("a stopped or unjudged scan does not end the build")

with tempfile.TemporaryDirectory() as tmp:
    # ── --diff-ids on the shapes a config really comes in ──────────────
    shapes = {
        "compact (kaniko, docker)": '{"architecture":"amd64","rootfs":{"type":"layers","diff_ids":["sha256:aa","sha256:bb"]},"history":[{"created_by":"x y"}]}',
        "indented (distroless, 2026-09-30)": '{\n  "rootfs": {\n    "type": "layers",\n    "diff_ids": [\n      "sha256:aa",\n      "sha256:bb"\n    ]\n  }\n}\n',
    }
    for label, cfg in shapes.items():
        p = subprocess.run(["sh", VERDICT, "--diff-ids"], input=cfg, capture_output=True, text=True, timeout=30)
        got = p.stdout.split()
        if got != ["sha256:aa", "sha256:bb"]:
            findings.append(f"`verdict.sh --diff-ids` on a {label} config gives {got}: the base's findings would be judged as the app's")
    p = subprocess.run(["sh", VERDICT, "--diff-ids"], input='{"config":{}}', capture_output=True, text=True, timeout=30)
    if p.returncode != 0 or p.stdout.strip():
        findings.append("`verdict.sh --diff-ids` on a config with no layers does not answer «none» quietly")

    # ── the split, as the Jenkinsfile runs it ──────────────────────────
    aw = re.search(r"(awk -F'\|' 'BEGIN \{.*?\n.*?' all\.txt)", body, re.S)
    if not aw:
        findings.append("the split of findings by layer (awk … all.txt) is not in the scan stage")
    else:
        with open(os.path.join(tmp, "base-diffids"), "w") as f:
            f.write("sha256:base1\nsha256:base2\n")
        with open(os.path.join(tmp, "all.txt"), "w") as f:
            f.write("CVE-1|HIGH|libssl3t64|1|2|2026-09-29||sha256:base2|t (debian 13.6)\n"
                    "CVE-2|HIGH|tar|1|2|2026-09-29|app/node_modules/tar/package.json|sha256:own1|Node.js\n")
        subprocess.run(["sh", "-c", aw.group(1)], cwd=tmp, timeout=30)
        read = lambda n: open(os.path.join(tmp, n)).read() if os.path.exists(os.path.join(tmp, n)) else ""
        if "CVE-1" not in read("inherited.txt") or "CVE-1" in read("own.txt"):
            findings.append("a finding in a base layer is not set apart as inherited: the base's CVE stops the app (build 1 on the Arch lab VM)")
        if "CVE-2" not in read("own.txt") or "CVE-2" in read("inherited.txt"):
            findings.append("a finding in the image's own layer is not judged: the app's own dependency slips through as the base's")

print("SCOPE: the tenant scan stage and pod read as code; verdict.sh --diff-ids run on compact, indented and "
      "layerless configs; the Jenkinsfile's split by layer run on a base and an own finding")
for x in findings:
    print(x)
