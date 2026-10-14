"""Check 258 — an exception is scoped to what the scan named, and an accepted risk says it was not measured.

MEASURED 2026-09-28 on a user's instance (their H-06): ten `aegis image request
node:22.23.1-alpine --allow …` wrote exceptions scoped to «Node.js
(node-pkg)» — the header trivy's table prints over EVERY npm package — and
trivy reported the same ten CVEs on the next scan. What an exception on a
language package has to name is the package's path (…/tar/package.json),
and one package can live at two paths (pacote, top-level and nested). The
door prints one `AEGIS_SCAN <image> <finding>` line per finding since
2026-09-30, with that path in it, and the command now scopes from those.

And plan/21 added a second kind of exception: a risk the operator ACCEPTS
without having measured it (upstream has not rebuilt yet). It says so in
its statement, lasts at most policy.yaml's acceptance_max_days, and is
never written for a CVE on the exploited-in-the-wild list.

This check RUNS the two pieces of libexec/aegis-image that decide it —
the scope and the writer — on the cases that define them, and the flag
parser on the two kinds given together.
"""
import datetime
import os
import re
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
IMG = os.path.join(ROOT, "libexec", "aegis-image")
findings = []

with open(IMG, encoding="utf-8") as f:
    src = f.read()

scope = re.search(r'targets="\$\(python3 - "\$slice" "\$cve" <<\'PY\'\n(.*?)\nPY\n', src, re.S)
writer = re.search(r"write_exception\(\) \{[^\n]*\n\s*python3 - \"\$IGNORE\" \"\$LIST_ROOT/k8s/base/platform/vuln-policy\" \"\$@\" <<'PY'\n(.*?)\nPY\n", src, re.S)
if not scope:
    findings.append("aegis-image has no scope reader for --allow (targets=…) in the shape this check runs")
if not writer:
    findings.append("write_exception does not read the vuln-policy directory beside the list: an accepted risk has no ceiling and no KEV list")
if not re.search(r'write_exception "\$cve" "\$UNTIL" "\$REASON" "\$EXC_KIND" "\$\{targets\[@\]\}"', src):
    findings.append("the exception is written without its kind: an accepted risk would read as a measurement")

T = datetime.date.today()
with tempfile.TemporaryDirectory() as tmp:
    if scope:
        sp = os.path.join(tmp, "scope.py")
        with open(sp, "w") as f:
            f.write(scope.group(1))

        def targets(console, cve):
            cp = os.path.join(tmp, "console.txt")
            with open(cp, "w") as f:
                f.write(console)
            p = subprocess.run([sys.executable, sp, cp, cve], capture_output=True, text=True, timeout=30)
            return [x for x in p.stdout.splitlines() if x]

        node = ("AEGIS_SCAN node:22.23.1-alpine CVE-2026-69199|HIGH|pacote|18.0.6|21.0.2|2026-08-03|"
                "usr/local/lib/node_modules/npm/node_modules/pacote/package.json|sha256:b|Node.js\n"
                "AEGIS_SCAN node:22.23.1-alpine CVE-2026-69199|HIGH|pacote|18.0.6|21.0.2|2026-08-03|"
                "usr/local/lib/node_modules/npm/node_modules/@npmcli/metavuln-calculator/node_modules/pacote/package.json|sha256:b|Node.js\n"
                "Node.js (node-pkg)\n==================\n│ pacote │ CVE-2026-69199 │ HIGH │\n")
        got = targets(node, "CVE-2026-69199")
        want = ["usr/local/lib/node_modules/npm/node_modules/pacote/package.json",
                "usr/local/lib/node_modules/npm/node_modules/@npmcli/metavuln-calculator/node_modules/pacote/package.json"]
        if got != want:
            findings.append(f"an npm finding is scoped to {got}, not to each package.json the scan named (a user's H-06: «Node.js (node-pkg)» matches nothing)")
        osl = "AEGIS_SCAN python:3.12-slim CVE-2026-75804|HIGH|openssl|3.5.7-1~deb13u2|3.5.7-1~deb13u3|2026-09-29||sha256:a|mirror.tar (debian 13.7)\n"
        got = targets(osl, "CVE-2026-75804")
        if got != ["*.tar (debian 13.7)"]:
            findings.append(f"an OS finding is scoped to {got}, not to «*.tar (debian 13.7)» (the watch scans watch.tar, the mirror mirror.tar)")
        old = "mirror.tar (alpine 3.24.1)\n==========================\n│ libssl3 │ CVE-2026-14456 │ HIGH │\n"
        got = targets(old, "CVE-2026-14456")
        if got != ["mirror.tar (alpine 3.24.1)"]:
            findings.append(f"a console with no AEGIS_SCAN lines no longer falls back to the table's target (got {got})")
        got = targets(osl, "CVE-2026-99999")
        if got:
            findings.append(f"a CVE the scan did not report gets a scope ({got}): an exception for something nobody measured on this image")

    if writer:
        wp = os.path.join(tmp, "writer.py")
        with open(wp, "w") as f:
            f.write(writer.group(1))
        vp = os.path.join(tmp, "vp")
        os.makedirs(vp)
        with open(os.path.join(ROOT, "seed", "platform", "k8s", "base", "platform", "vuln-policy", "policy.yaml")) as f:
            pol = f.read()
        most = int(re.search(r"^acceptance_max_days:\s*(\d+)", pol, re.M).group(1))
        with open(os.path.join(vp, "policy.yaml"), "w") as f:
            f.write(pol)
        with open(os.path.join(vp, "kev.txt"), "w") as f:
            f.write("# CISA KEV dateReleased=2026-09-29\nCVE-2026-9000001\n")

        def write(cve, days, kind):
            ig = os.path.join(tmp, "trivyignore.yaml")
            with open(ig, "w") as f:
                f.write("vulnerabilities:\n  - id: CVE-2020-0001\n    paths: [\"x\"]\n    statement: \"m. Measured 2026-01-01.\"\n    expired_at: 2026-12-31\n")
            until = (T + datetime.timedelta(days=days)).isoformat()
            p = subprocess.run([sys.executable, wp, ig, vp, cve, until, "upstream has not rebuilt", kind, "*.tar (debian 13.7)"],
                               capture_output=True, text=True, timeout=30)
            with open(ig) as f:
                return p.returncode, f.read(), p.stderr

        rc, txt, err = write("CVE-2026-75804", most - 1, "accepted")
        if rc != 0:
            findings.append(f"an accepted risk inside the policy's ceiling is refused: {err.strip()[:140]}")
        elif "Risk accepted, not measured" not in txt or f"Accepted {T.isoformat()}" not in txt or "Measured" in txt.split("CVE-2026-75804")[-1]:
            findings.append("an accepted risk is written as if it had been measured: the next person reads a measurement nobody made")
        rc, txt, err = write("CVE-2026-75804", most + 1, "accepted")
        if rc == 0:
            findings.append(f"an accepted risk of {most + 1} days is written: the policy's acceptance_max_days ({most}) does not bound it")
        rc, txt, err = write("CVE-2026-9000001", 5, "accepted")
        if rc == 0:
            findings.append("a CVE exploited in the wild is accepted: it has no window anywhere, and an unmeasured acceptance is the widest one")
        rc, txt, err = write("CVE-2026-75804", most + 30, "measured")
        if rc != 0:
            findings.append(f"a measured exception beyond the acceptance ceiling (but within 12 months) is refused: {err.strip()[:140]}")

# the report reads the door's verdict, not the table (the Arch lab VM, 2026-09-30:
# «3 blocking findings» for 11, and the exception pointed at «Node.js (node-pkg)»)
rep = re.search(r"report_scan\(\) \{[^\n]*\n\s*python3 - \"\$1\" \"\$2\" \"\$\{3:-\$2\}\" <<'PY'\n(.*?)\nPY\n", src, re.S)
if not rep:
    findings.append("report_scan does not take the image as asked: it cannot print the one-call command")
else:
    with tempfile.TemporaryDirectory() as tmp:
        rp = os.path.join(tmp, "rep.py")
        with open(rp, "w") as f:
            f.write(rep.group(1))
        cp = os.path.join(tmp, "slice.txt")
        with open(cp, "w") as f:
            f.write("Node.js (node-pkg)\n==================\n│ tar │ CVE-2026-59873 │ CRITICAL │\n"
                    "AEGIS_VERDICT n:1 block|CVE-2026-59873|CRITICAL|tar|usr/lib/npm/tar/package.json|2026-07-08|2026-07-23|published 2026-07-08, its window closed on 2026-07-23\n"
                    "AEGIS_VERDICT n:1 block|CVE-2026-9496|HIGH|pacote|usr/lib/npm/pacote/package.json|2026-05-26|2026-06-25|published 2026-05-26, its window closed on 2026-06-25\n"
                    "AEGIS_VERDICT n:1 block|CVE-2026-9496|HIGH|pacote|usr/lib/npm/x/node_modules/pacote/package.json|2026-05-26|2026-06-25|published 2026-05-26, its window closed on 2026-06-25\n"
                    "AEGIS_VERDICT n:1 debt|CVE-2026-102276|HIGH|brace-expansion|usr/lib/npm/b/package.json|2026-09-28|2026-10-28|inside its window\n")
        r = subprocess.run([sys.executable, rp, cp, "n:1", "node:22"], capture_output=True, text=True, timeout=30)
        out = r.stderr
        if "3 finding(s) stopped n:1; 1 would have entered" not in out:
            findings.append(f"the report does not count what the verdict stopped and what it would have let in: {out.strip()[:160]}")
        if "Node.js (node-pkg)" in out:
            findings.append("the report still names «Node.js (node-pkg)» — the scope that matched nothing on a user's instance")
        if "usr/lib/npm/x/node_modules/pacote/package.json" not in out:
            findings.append("the report does not name each path a stopped finding lives at")
        if not re.search(r"aegis image request node:22 --accept CVE-2026-59873,CVE-2026-9496 --until \d{4}-\d{2}-\d{2}", out):
            findings.append("the report does not hand over ONE call accepting every stopped CVE (13 calls and 13 mirror runs is the explosion plan/21 exists to end)")

# a list of CVEs is validated as a list
p2 = subprocess.run(["bash", IMG, "request", "python:3.12-slim", "--accept", "CVE-2026-1111,oops",
                     "--until", "2026-10-10", "--reason", "r"], capture_output=True, text=True, timeout=30,
                    env={"PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", "/tmp")})
if p2.returncode == 0 or "not a CVE identifier" not in (p2.stderr + p2.stdout):
    findings.append(f"a CVE list with something that is not a CVE in it is not refused (rc {p2.returncode})")

# the two kinds are one choice
p = subprocess.run(["bash", IMG, "request", "python:3.12-slim", "--allow", "CVE-2026-1111", "--accept", "CVE-2026-2222",
                    "--until", "2026-10-10", "--reason", "r"], capture_output=True, text=True, timeout=30,
                   env={"PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", "/tmp")})
if p.returncode == 0 or "either measured or accepted" not in (p.stderr + p.stdout):
    findings.append(f"--allow and --accept together are not refused (rc {p.returncode})")

print("SCOPE: the scope reader on 4 consoles (npm at two paths, OS, an old table, a CVE not reported), "
      "the writer on 4 exceptions (accepted in and past the ceiling, accepted KEV, measured), the report on "
      "the door's verdict, the flag parser")
for x in findings:
    print(x)
