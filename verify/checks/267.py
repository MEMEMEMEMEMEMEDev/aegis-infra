"""Check 267 — the watch keeps the books.

plan/21 made the door let findings in as DEBT, with a due date. Debt that
nobody writes down is the old red with extra steps: until 2026-10-02
image-watch published counts per image (no date, no owner), and the
exploited-in-the-wild list that verdict.sh trusts for three days was
said to be refreshed by the watch «every morning» — and nothing did it.

image-watch/ledger.sh writes the books from the watch's scans through
verdict.sh. This sidecar RUNS it on the cases that define them:
  · a finding inside its window is debt, due at publication + window;
    past it, overdue; on the exploited list, exploited;
  · a finding with no publication date runs on the day it was first seen,
    and keeps that day tomorrow (yesterday's ledger is read);
  · an image scanned clean is a `clean` line; an image not scanned, or
    whose findings cannot be judged, is `unmeasured` — never an absence;
  · an exploited list too old to trust is a line of its own;
  · the exceptions in force are listed with their class; lapsed ones not;
  · the same inputs give the same bytes (the watch commits on change);
  · --metrics gives explicit zeros and carves the last third out of debt.
And it reads the watch: the scan keeps verdict.sh's template, the books
are written from yesterday's, the publish commits only the two files,
the exploited list is fetched with a guard against a short download, and
the seed does not take the instance's list back.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
P = os.path.join(ROOT, "seed", "platform")
LEDGER = os.path.join(P, "image-watch", "ledger.sh")
VP = os.path.join(P, "k8s", "base", "platform", "vuln-policy")
WATCH = os.path.join(P, "image-watch", "Jenkinsfile")
findings = []

for f in (LEDGER, os.path.join(VP, "verdict.sh"), os.path.join(VP, "policy.yaml"), WATCH):
    if not os.path.isfile(f):
        print(f"{os.path.relpath(f, ROOT)} is missing")
        sys.exit(0)

pol = dict(re.findall(r"^([a-z_]+):[ \t]*([0-9]+)", open(os.path.join(VP, "policy.yaml")).read(), re.M))
HIGH = int(pol["high_days"])

shells = [["sh"]]
if shutil.which("busybox"):
    shells.append(["busybox", "sh"])


def run(shell, tmp, args, today, kevday="2026-10-01"):
    vp = os.path.join(tmp, "vp")
    os.makedirs(vp, exist_ok=True)
    for f in ("verdict.sh", "policy.yaml"):
        shutil.copy(os.path.join(VP, f), vp)
    with open(os.path.join(vp, "kev.txt"), "w") as f:
        f.write(f"# CISA KEV catalogVersion=t dateReleased={kevday} count=1\nCVE-2026-0000009\n")
    env = {"PATH": os.environ["PATH"], "VP": vp, "TODAY": today,
           "IGNOREFILE": os.path.join(tmp, "ign.yaml")}
    p = subprocess.run(shell + [LEDGER] + args, capture_output=True, text=True, env=env, timeout=60, cwd=tmp)
    return p.returncode, p.stdout, p.stderr


def rows(text):
    return [l.split("|") for l in text.splitlines() if l and not l.startswith("#")]


def find(rs, state=None, image=None, cve=None):
    return [r for r in rs if (state is None or r[0] == state) and (image is None or r[1] == image)
            and (cve is None or r[4] == cve)]


scope = []
for sh in shells:
    who = " ".join(sh)
    with tempfile.TemporaryDirectory() as tmp:
        w = lambda name, text: open(os.path.join(tmp, name), "w").write(text)  # noqa: E731
        w("a.txt", "\n".join([
            "CVE-2026-0000001|HIGH|libssl3|3.5.7-1|3.5.7-2, 3.6.0-1|2026-09-28||sha256:a|py (debian 13)",
            "CVE-2026-0000002|CRITICAL|libc|2.41|2.42|2026-09-01||sha256:a|py (debian 13)",
            "CVE-2026-0000009|HIGH|curl|8.1|8.2|2026-09-30||sha256:a|py (debian 13)",
            "CVE-2026-0000003|HIGH|npm|10|11||usr/lib/node_modules/npm/package.json|sha256:b|Node.js",
        ]) + "\n")
        w("clean.txt", "")
        w("bad.txt", "CVE-2026-0000004|HIGH|x|1\n")
        w("inv", "\n".join([
            f"python|mirror|sha256:111|upstream|{tmp}/a.txt",
            f"node|base|sha256:222|the base loop|{tmp}/clean.txt",
            "garage|mirror|sha256:333|upstream|",
            f"broken|mirror|sha256:444|upstream|{tmp}/bad.txt",
        ]) + "\n")
        w("ign.yaml", "# c\nvulnerabilities:\n"
          "  - id: CVE-2025-0000001   # x\n    paths: [\"usr/local/bin/gosu\"]\n"
          "    statement: \"not linked. Measured 2026-07-26.\"\n    expired_at: 2027-01-31\n"
          "  - id: CVE-2026-0000002\n    paths: [\"a\"]\n"
          "    statement: \"Risk accepted, not measured: upstream. Accepted 2026-10-01.\"\n    expired_at: 2026-12-01\n"
          "  - id: CVE-2020-0000003\n    paths: [\"x\"]\n    statement: \"old\"\n    expired_at: 2026-01-01\n")
        rc, out, err = run(sh, tmp, ["inv"], "2026-10-02")
        if rc != 0:
            findings.append(f"[{who}] the ledger was not written (rc {rc}): {err.strip()[:160]}")
            continue
        rs = rows(out)
        if any(len(r) != 14 for r in rs):
            findings.append(f"[{who}] a ledger line does not carry the 14 fields")
        d = find(rs, "debt", "python", "CVE-2026-0000001")
        if not d or d[0][12] != "2026-10-28" or d[0][8] != "3.5.7-2, 3.6.0-1":
            findings.append(f"[{who}] a HIGH published 2026-09-28 is not debt due 2026-10-28 with its fix versions intact")
        if not find(rs, "overdue", "python", "CVE-2026-0000002"):
            findings.append(f"[{who}] a CRITICAL past its window is not overdue")
        if not find(rs, "exploited", "python", "CVE-2026-0000009"):
            findings.append(f"[{who}] a finding on the exploited list is not exploited")
        fs = find(rs, None, "python", "CVE-2026-0000003")
        if not fs or fs[0][10] != "2026-10-02" or fs[0][11] != "first-seen":
            findings.append(f"[{who}] a dateless finding does not run on the day it was first seen")
        if not find(rs, "clean", "node"):
            findings.append(f"[{who}] an image scanned clean is not in the books (clean and absent read the same)")
        if not find(rs, "unmeasured", "garage"):
            findings.append(f"[{who}] an image the watch could not scan is absent from the books instead of unmeasured")
        if not find(rs, "unmeasured", "broken"):
            findings.append(f"[{who}] an image whose findings cannot be judged is not unmeasured")
        ex = {r[4]: r for r in find(rs, "excused")}
        if ex.get("CVE-2025-0000001", [""] * 14)[11] != "measured" or ex.get("CVE-2026-0000002", [""] * 14)[11] != "accepted":
            findings.append(f"[{who}] the exceptions in force are not listed with their class")
        if "CVE-2020-0000003" in ex:
            findings.append(f"[{who}] a lapsed exception is listed as in force")
        if find(rs, "unmeasured", "exploited-list"):
            findings.append(f"[{who}] a one-day-old exploited list is reported as too old")
        rc2, out2, _ = run(sh, tmp, ["inv"], "2026-10-02")
        if out2 != out:
            findings.append(f"[{who}] the same inputs gave two different ledgers: the watch would commit every morning")
        w("led1", out)
        # Tomorrow and beyond: the first-seen clock is kept; a stale list is said.
        rc, out3, err = run(sh, tmp, ["inv", "led1"], "2026-11-20", kevday="2026-10-01")
        rs3 = rows(out3)
        if any(len(r) != 14 for r in rs3):
            findings.append(f"[{who}] a line of the second morning's ledger does not carry the 14 fields "
                            f"({[r[1] for r in rs3 if len(r) != 14]}): the series and aegis vulns skip it")
        fs = find(rs3, None, "python", "CVE-2026-0000003")
        if not fs or fs[0][10] != "2026-10-02" or fs[0][0] != "overdue":
            findings.append(f"[{who}] yesterday's first-seen day was not kept: the window restarts every morning")
        stale = find(rs3, "unmeasured", "exploited-list")
        if not stale or "50 days old" not in stale[0][9]:
            findings.append(f"[{who}] an exploited list 50 days old is not said in the books, in the field its readers read")
        # The series.
        w("led2", out)
        rc, met, err = run(sh, tmp, ["--metrics", "led2"], "2026-10-20")
        m = dict(re.findall(r"^(\S+\}) (\d+)$", met, re.M))
        def mv(k):
            return m.get(k)
        if mv('aegis_vuln_findings{image="node",kind="base",state="debt"}') != "0":
            findings.append(f"[{who}] a clean image has no explicit zero in the series")
        if mv('aegis_vuln_findings{image="python",kind="mirror",state="due_soon"}') != "1" \
                or mv('aegis_vuln_findings{image="python",kind="mirror",state="debt"}') != "1":
            findings.append(f"[{who}] the last third of a window is not carved out of debt as due_soon")
        if mv('aegis_vuln_unmeasured{image="garage",kind="mirror"}') != "1":
            findings.append(f"[{who}] an unmeasured image is not 1 in aegis_vuln_unmeasured")
        if mv('aegis_vuln_unmeasured{image="exploited-list",kind="kev"}') != "0":
            findings.append(f"[{who}] a fresh exploited list has no explicit zero in the series: VulnExploitedListStale keeps firing two days after the cure")
        w("led3", out3)
        rc, met3, err = run(sh, tmp, ["--metrics", "led3"], "2026-11-20")
        if 'aegis_vuln_unmeasured{image="exploited-list",kind="kev"} 1' not in met3:
            findings.append(f"[{who}] a stale exploited list is not 1 in aegis_vuln_unmeasured")
        if 'aegis_vuln_findings{image="garage"' in met:
            findings.append(f"[{who}] an unmeasured image carries finding counts (a zero that was not measured)")
    # --inherit: the mirror's exceptions hold on an app's INHERITED layers only.
    with tempfile.TemporaryDirectory() as tmp:
        exc = "CVE-2026-0000001|HIGH|libssl3t64|1|2|2026-09-29||sha256:base|t (debian 13.6)"
        base_ex = "CVE-2026-0000014|HIGH|libssl3t64|1|2|2026-08-13||sha256:base|t (debian 13.6)"
        own_ex = "CVE-2026-0000014|HIGH|libssl3|1|2|2026-08-13||sha256:own|t (alpine 3.24)"
        open(os.path.join(tmp, "exc"), "w").write(exc + "\n")
        open(os.path.join(tmp, "full"), "w").write("\n".join([exc, base_ex, own_ex]) + "\n")
        open(os.path.join(tmp, "base"), "w").write("sha256:base\n")
        env = {"PATH": os.environ["PATH"]}
        p = subprocess.run(sh + [LEDGER, "--inherit", "exc", "full", "base"], capture_output=True, text=True, env=env, cwd=tmp)
        got = p.stdout.splitlines()
        if p.returncode != 0 or got != [exc, own_ex]:
            findings.append(f"[{who}] --inherit does not keep an excused finding excused on the base's layer and back on the app's own (got {got})")
        p = subprocess.run(sh + [LEDGER, "--inherit", "exc", "full", "nowhere"], capture_output=True, text=True, env=env, cwd=tmp)
        if sorted(p.stdout.splitlines()) != sorted([exc, base_ex, own_ex]):
            findings.append(f"[{who}] with no base layers known, --inherit excuses something: it has to report, never hide")
        open(os.path.join(tmp, "full2"), "w").write("broken|line\n")
        p = subprocess.run(sh + [LEDGER, "--inherit", "exc", "full2", "base"], capture_output=True, text=True, env=env, cwd=tmp)
        if p.returncode != 3:
            findings.append(f"[{who}] --inherit over a malformed scan line exits {p.returncode}, not 3: an unjudged scan reads as judged")
    scope.append(who)

# ── the watch ──
src = open(WATCH, encoding="utf-8").read()
code = "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("//"))
if 'verdict.sh" --template' not in code:
    findings.append("the watch does not scan with verdict.sh's template: the books would have no publication date")
if not re.search(r"sh image-watch/ledger\.sh ledger-in/inventory\.txt image-watch/ledger\.txt", code):
    findings.append("the watch does not write the books from yesterday's (image-watch/ledger.txt)")
if "LEDGER_METRICS" not in code.split("stage('report')")[-1] or "aegis_vuln_ledger_written" not in code:
    findings.append("the report does not push the books' series and whether they were written")
pub = code.split("stage('publish')")[-1].split("stage('loop')")[0] if "stage('publish')" in code else ""
if not pub:
    findings.append("the watch has no publish stage: the books never reach the platform repo")
else:
    if not re.search(r"grep -vxF -e image-watch/ledger\.txt -e \"\$\{KEV_REL\}\"", pub):
        findings.append("the publish has no guard: the commit may carry more than the ledger and the list")
    if not re.search(r'cp "\$\{WORKSPACE\}/\$\{KEV_REL\}"', pub):
        findings.append("the publish does not carry the exploited list: the tenants' ConfigMap never moves")
kev = code.split("stage('exploited list')")[-1].split("stage('inventory')")[0] if "stage('exploited list')" in code else ""
if not kev or "known_exploited_vulnerabilities.json" not in kev:
    findings.append("the watch does not fetch the exploited-in-the-wild list")
elif not re.search(r'\[ "\$NEW" -lt \$\(\( OLD \* 9 / 10 \)\) \]', kev):
    findings.append("a short download of the exploited list would replace the copy (no shrink guard)")

sys.path.insert(0, os.path.join(ROOT, "lib"))
from aegis import seed  # noqa: E402
for rel in ("k8s/base/platform/vuln-policy/kev.txt", "image-watch/ledger.txt"):
    if not seed.instance_owns(rel):
        findings.append(f"aegis seed treats {rel} as the seed's: an apply rolls the watch's copy back")

for x in findings:
    print(x)
print(f"SCOPE: ledger.sh run under {', '.join(scope) or 'no shell'} on 4 images, 3 exceptions, two mornings and the series; the watch's stages and the seed's ownership read")
