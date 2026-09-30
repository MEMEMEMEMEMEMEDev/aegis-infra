"""Check 255 — one verdict decides what a known vulnerability costs.

MEASURED 2026-09-30, alpha-arch (the first run of the ALPHA series): a
clean install died in phase 80 because Debian had fixed two OpenSSL CVEs
the day before (CVE-2026-75804, CVE-2026-84782, 3.5.7-1~deb13u3) and the
upstream python:3.12-slim and nodejs-distroless:22 had not been rebuilt.
Every scan in aegis had one answer, and nothing the operator could do made
those images clean. Two days earlier, on another instance, ten CVEs in the
npm that ships inside a BUILD image stopped a tenant's first build.

The class is not a threshold, it is a missing question: whether the finding
is the CHANGE's or TIME's. vuln-policy/verdict.sh asks it, once, for every
job that scans (plan/21 of the registro). This sidecar RUNS it — against a
copy of the seed's own policy.yaml — on the cases that define it: what a
new admission may carry and until when, what a change may not bring, what
stays debt, what the exploited-in-the-wild list does, and that a verdict
that cannot be given says so (rc 3) instead of reading as clean. And the
ConfigMap has to carry the three files to the tenants' agents.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
VP = os.path.join(ROOT, "seed", "platform", "k8s", "base", "platform", "vuln-policy")
VERDICT = os.path.join(VP, "verdict.sh")
POLICY = os.path.join(VP, "policy.yaml")
findings = []

for f in (VERDICT, POLICY):
    if not os.path.isfile(f):
        print(f"{os.path.relpath(f, ROOT)} is missing: no verdict can be given")
        sys.exit(0)

with open(POLICY, encoding="utf-8") as f:
    pol = dict(re.findall(r"^([a-z_]+):[ \t]*([0-9]+)", f.read(), re.M))
for k in ("critical_days", "high_days", "kev_max_age_days", "acceptance_max_days"):
    if k not in pol:
        findings.append(f"policy.yaml does not say {k}")
if findings:
    for x in findings:
        print(x)
    sys.exit(0)
CRIT, HIGH, KEVAGE = int(pol["critical_days"]), int(pol["high_days"]), int(pol["kev_max_age_days"])

TODAY = "2026-09-30"
KEVDAY = "2026-09-29"


def line(cve, sev, pkg, pub, path="", installed="1.0", fixed="1.1, 2.0"):
    return f"{cve}|{sev}|{pkg}|{installed}|{fixed}|{pub}|{path}|sha256:x|t (debian 13.7)"


def run(tmp, findings_lines, reference_lines=None, today=TODAY, kev=KEVDAY, policy=POLICY, env_extra=None):
    fp = os.path.join(tmp, "findings.txt")
    with open(fp, "w", encoding="utf-8") as f:
        f.write("\n".join(findings_lines) + ("\n" if findings_lines else ""))
    args = ["sh", VERDICT, fp]
    if reference_lines is not None:
        rp = os.path.join(tmp, "reference.txt")
        with open(rp, "w", encoding="utf-8") as f:
            f.write("\n".join(reference_lines) + ("\n" if reference_lines else ""))
        args.append(rp)
    kp = os.path.join(tmp, "kev.txt")
    with open(kp, "w", encoding="utf-8") as f:
        f.write(f"# CISA KEV catalogVersion=t dateReleased={kev} count=1\nCVE-2026-9000001\n")
    env = {"PATH": os.environ["PATH"], "TODAY": today, "KEV": kp, "POLICY": policy}
    env.update(env_extra or {})
    p = subprocess.run(args, capture_output=True, text=True, env=env, timeout=30)
    out = {}
    for ln in p.stdout.splitlines():
        parts = ln.split("|")
        if len(parts) == 8:
            out[parts[1]] = parts
    return p.returncode, out, p.stderr


def expect(label, got, cve, verdict, due=None):
    rc, out, err = got
    if cve not in out:
        findings.append(f"{label}: {cve} has no verdict line (rc {rc}): {err.strip()[:160]}")
        return
    if out[cve][0] != verdict:
        findings.append(f"{label}: {cve} is «{out[cve][0]}» ({out[cve][7]}), the policy says «{verdict}»")
    elif due and out[cve][6] != due:
        findings.append(f"{label}: {cve} is due {out[cve][6]}, the policy says {due}")


with tempfile.TemporaryDirectory() as tmp:
    # the case of 2026-09-30: HIGH published yesterday, a new admission → debt, due +HIGH days
    fresh = line("CVE-2026-75804", "HIGH", "libssl3t64", "2026-09-29")
    old = line("CVE-2026-13149", "HIGH", "brace-expansion", "2026-06-30",
               path="usr/local/lib/node_modules/npm/node_modules/brace-expansion/package.json")
    crit = line("CVE-2026-9000002", "CRITICAL", "zlib", "2026-09-20")
    kev = line("CVE-2026-9000001", "CRITICAL", "libfoo", "2026-09-28")
    nodate = line("CVE-2026-9000003", "HIGH", "libbar", "")

    import datetime
    d0 = datetime.date(2026, 9, 29)
    due_fresh = (d0 + datetime.timedelta(days=HIGH)).isoformat()
    due_crit = (datetime.date(2026, 9, 20) + datetime.timedelta(days=CRIT)).isoformat()

    # ── a new admission ────────────────────────────────────────────────
    g = run(tmp, [fresh])
    expect("new admission, inside its window", g, "CVE-2026-75804", "debt", due_fresh)
    if g[0] != 0:
        findings.append(f"a new admission with only in-window debt stops (rc {g[0]}): phase 80 dies as on 2026-09-30")
    g = run(tmp, [fresh, old, crit, kev, nodate])
    expect("new admission, past its window", g, "CVE-2026-13149", "block")
    expect("new admission, critical inside its window", g, "CVE-2026-9000002", "debt", due_crit)
    expect("new admission, exploited in the wild", g, "CVE-2026-9000001", "block")
    expect("new admission, no publication date", g, "CVE-2026-9000003", "block")
    if g[0] != 1:
        findings.append(f"a new admission with findings that stop exits rc {g[0]}, not 1")
    stale = (datetime.date(2026, 9, 29) - datetime.timedelta(days=KEVAGE + 1)).isoformat()
    g = run(tmp, [fresh], kev=stale)
    expect("new admission, exploited-in-the-wild list too old", g, "CVE-2026-75804", "block")

    # ── a change, judged against what runs ─────────────────────────────
    g = run(tmp, [fresh, old, kev], reference_lines=[fresh, old, kev])
    expect("change, inherited inside its window", g, "CVE-2026-75804", "debt", due_fresh)
    expect("change, inherited past its window", g, "CVE-2026-13149", "overdue")
    expect("change, inherited and exploited", g, "CVE-2026-9000001", "exploited")
    if g[0] != 0:
        findings.append(f"a change that brings nothing new stops (rc {g[0]}): the urgent fix would be blocked by what already runs")
    g = run(tmp, [fresh, crit], reference_lines=[fresh])
    expect("change, the change brings it", g, "CVE-2026-9000002", "block")
    if g[0] != 1:
        findings.append(f"a change that brings a new finding exits rc {g[0]}, not 1")
    moved = line("CVE-2026-75804", "HIGH", "libssl3t64", "2026-09-29", installed="1.0.5")
    g = run(tmp, [moved], reference_lines=[fresh])
    expect("change, same exposure at another installed version", g, "CVE-2026-75804", "debt")
    g = run(tmp, [fresh], reference_lines=[])
    expect("change, what runs is clean", g, "CVE-2026-75804", "block")

    # ── a verdict that cannot be given is never clean ──────────────────
    rc = run(tmp, [fresh], policy=os.path.join(tmp, "no-policy.yaml"))[0]
    if rc != 3:
        findings.append(f"with no policy the verdict exits rc {rc}, not 3: an unjudged scan would read as judged")
    rc = run(tmp, ["CVE-1|HIGH|p"])[0]
    if rc != 3:
        findings.append(f"a malformed finding line exits rc {rc}, not 3")
    p = subprocess.run(["sh", VERDICT, os.path.join(tmp, "findings.txt"), os.path.join(tmp, "absent.txt")],
                       capture_output=True, text=True, env={"PATH": os.environ["PATH"], "TODAY": TODAY}, timeout=30)
    if p.returncode != 3:
        findings.append(f"a change whose reference file is missing exits rc {p.returncode}, not 3: "
                        f"it would be judged as a change against nothing")

    # ── busybox, which is what the trivy container runs ────────────────
    bb = shutil.which("busybox")
    if bb:
        bdir = os.path.join(tmp, "bb")
        os.makedirs(bdir)
        for a in ("sh", "awk", "dirname", "date", "printf"):
            os.symlink(bb, os.path.join(bdir, a))
        g = run(tmp, [fresh, old], reference_lines=[fresh], env_extra={"PATH": bdir})
        expect("busybox, inherited", g, "CVE-2026-75804", "debt", due_fresh)
        expect("busybox, the change brings it", g, "CVE-2026-13149", "block")
        engines = "sh+awk of this runner and busybox"
    else:
        engines = "sh+awk of this runner (no busybox here)"

# ── the template the callers use yields the nine fields ────────────────
p = subprocess.run(["sh", VERDICT, "--template"], capture_output=True, text=True, timeout=30)
tpl = p.stdout.strip()
inner = re.search(r"\{\{range \.Vulnerabilities\}\}(.*)\{\{\"\\n\"\}\}\{\{end\}\}", tpl)
if not inner:
    findings.append("`verdict.sh --template` does not print one line per vulnerability")
else:
    body = re.sub(r"\{\{if [^}]*\}\}.*?\{\{end\}\}", "X", inner.group(1))
    if body.count("|") != 8:
        findings.append(f"`verdict.sh --template` prints {body.count('|') + 1} fields, the verdict reads 9")
    if ".PublishedDate.Format" not in tpl or ".PkgPath" not in tpl:
        findings.append("`verdict.sh --template` does not carry the publication date and the package path")

# ── the ConfigMap carries the three files to the tenants' agents ───────
with open(os.path.join(VP, "kustomization.yaml"), encoding="utf-8") as f:
    kz = f.read()
for need in ("policy.yaml", "verdict.sh", "kev.txt"):
    if not re.search(rf"^\s*-\s*{re.escape(need)}\s*$", kz, re.M):
        findings.append(f"the aegis-vuln-policy ConfigMap does not carry {need}: a tenant's build could not read it")
if "name: aegis-vuln-policy" not in kz or "disableNameSuffixHash: true" not in kz:
    findings.append("the ConfigMap is not `aegis-vuln-policy` without a name suffix: pod templates mount it by name")
# its own Application, in a file the SEED owns: jenkins-secrets' kustomization
# is the instance's, and `aegis seed apply` never brings a change to it
# (measured on alpha-arch, 2026-09-30) — an installed instance would never
# get the policy.
apps = os.path.join(ROOT, "seed", "platform", "k8s", "argocd-apps", "ci-supply-tenants.yaml")
with open(apps, encoding="utf-8") as f:
    docs = [d for d in __import__("yaml").safe_load_all(f) if d]
app = next((d for d in docs if (d.get("metadata") or {}).get("name") == "vuln-policy"), None)
if not app:
    findings.append("no Application vuln-policy in k8s/argocd-apps/ci-supply-tenants.yaml: the ConfigMap never reaches jenkins-system")
else:
    sp = app.get("spec") or {}
    if (sp.get("source") or {}).get("path") != "k8s/base/platform/vuln-policy" \
            or (sp.get("destination") or {}).get("namespace") != "jenkins-system":
        findings.append("the vuln-policy Application does not carry k8s/base/platform/vuln-policy into jenkins-system")
    if not (sp.get("syncPolicy") or {}).get("automated"):
        findings.append("the vuln-policy Application does not sync by itself: this morning's KEV list would wait for a person")

print(f"SCOPE: 16 cases through verdict.sh ({engines}) against the seed's policy "
      f"(critical {CRIT}d, high {HIGH}d, KEV trusted {KEVAGE}d); its template; the ConfigMap")
for x in findings:
    print(x)
