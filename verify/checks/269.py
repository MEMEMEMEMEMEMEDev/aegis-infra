"""Check 269 — the watch looks at what runs in the tenants.

S11 of docs/protocols/images.md, named on purpose since v1: image-watch
scanned what is MIRRORED and the BASES, never the app images that run.
An app built on last month's base carried its CVEs, and after a base
rebuild an app whose own layer failed its scan stayed on the old base
while the base's alert cleared. plan/21 needs the books to cover what
runs, so the gap is closed (2026-10-02).

Stage `apps` of image-watch/Jenkinsfile reads, for every repo a contract
in orgs/ names, the digest its k8s/overlays/dev/kustomization.yaml
deploys. This sidecar takes the stage's two shell blocks AS GROOVY HANDS
THEM TO THE SHELL (`\\\\` → `\\`), runs them over fixture contracts (a
top-level repo and a service's, quoted and commented, a postgres with
none) and a fixture overlay (name, newName, a never-built 64-zero entry),
and asserts what comes out. Then it reads the stage: the clone is depth
1 with the token never in argv, nothing is pushed, the serving stage
scans apps without the mirror's ignorefile, and the books name the app's
repo as who fixes it.

AND THE EXCEPTIONS OF ITS BASE (found on alpha-arch, 2026-10-02, the first
run of the series): the first version scanned apps WITHOUT the mirror's
trivyignore.yaml — this check even required it — and the portfolio carried
CVE-2026-14456 as OVERDUE, a CVE measured and excused in nodejs-distroless,
the base it stands on. Every round red over the same bytes the mirror had
excused. Now an app is scanned with the exceptions AND without them, its
FROMs (by digest) give the base's layers, and ledger.sh --inherit keeps an
excused finding excused only on an inherited layer (check 267 runs it).
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
W = os.path.join(ROOT, "seed", "platform", "image-watch", "Jenkinsfile")
findings = []
src = open(W, encoding="utf-8").read()
if "stage('apps')" not in src:
    print("image-watch has no `apps` stage: what runs in the tenants is never scanned (S11 open again)")
    sys.exit(0)
stage = src[src.index("stage('apps')"):src.index("stage('serving')")]
blocks = re.findall(r"script: '''\n(.*?)'''", stage, re.S)
if len(blocks) != 2:
    print(f"the apps stage carries {len(blocks)} shell block(s), not 2 (the repos, the overlay): re-aim this check")
    sys.exit(0)
unesc = lambda t: t.replace("\\\\", "\\")  # noqa: E731
repos_sh, clone_sh = unesc(blocks[0]), unesc(blocks[1])

with tempfile.TemporaryDirectory() as tmp:
    os.makedirs(os.path.join(tmp, "orgs"))
    open(os.path.join(tmp, "orgs", "vet.yaml"), "w").write(
        "version: 1\norganizacion: vet\nrepo: git@github.com:Own/vet-app.git\nservicios:\n"
        "  - nombre: front\n    tipo: estatico\n    repo: \"github.com/Own/vet-front\"   # the front\n"
        "  - nombre: db\n    tipo: postgres\n")
    open(os.path.join(tmp, "orgs", "infra.yaml"), "w").write(
        "version: 1\norganizacion: infra\nservicios:\n  - nombre: db\n    tipo: postgres\n")
    p = subprocess.run(["sh", "-c", repos_sh], capture_output=True, text=True, cwd=tmp)
    got = sorted(p.stdout.split("\n"))
    want = sorted(["vet git@github.com:Own/vet-app.git", "vet github.com/Own/vet-front", ""])
    if p.returncode != 0 or [g for g in got if g] != [w for w in want if w]:
        findings.append(f"the repos of the contracts are not read as «org repo» lines (got {[g for g in got if g]})")

    sc = os.path.join(tmp, ".apps", "k8s", "overlays", "dev")
    os.makedirs(sc)
    open(os.path.join(sc, "kustomization.yaml"), "w").write(
        "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n  - ../../base\n"
        "images:\n"
        "  - name: registry.registry-system.svc.cluster.local:5000/vet-front   # the front\n"
        "    digest: sha256:" + "1" * 64 + "   # written by build 7\n"
        "  - name: \"registry.registry-system.svc.cluster.local:5000/vet-api\"\n"
        "    newName: registry.registry-system.svc.cluster.local:5000/vet-api2\n"
        "    digest: sha256:" + "0" * 64 + "\n"
        "patches: []\n")
    with open(os.path.join(tmp, ".apps", "Containerfile"), "w") as cf:
        cf.write("# FROM registry.registry-system.svc.cluster.local:5000/commented@sha256:" + "9" * 64 + "\n"
                 "FROM --platform=linux/amd64 registry.registry-system.svc.cluster.local:5000/nodejs-distroless:22@sha256:" + "2" * 64 + "\n"
                 "COPY dist/ ./public/\n")
    tail = clone_sh[clone_sh.index('O="'):]
    p = subprocess.run(["sh", "-c", 'SCRATCH="$PWD/.apps"\n' + tail], capture_output=True, text=True, cwd=tmp)
    lines = [l for l in p.stdout.splitlines() if l.strip()]
    froms = [l for l in lines if l.startswith("FROM ")]
    lines = [l for l in lines if not l.startswith("FROM ")]
    if froms != ["FROM registry.registry-system.svc.cluster.local:5000/nodejs-distroless:22@sha256:" + "2" * 64]:
        findings.append(f"the clone does not say the app's FROM by digest (a commented one skipped, --platform read past): got {froms}")
    if lines != ["registry.registry-system.svc.cluster.local:5000/vet-front sha256:" + "1" * 64,
                 "registry.registry-system.svc.cluster.local:5000/vet-api2 sha256:" + "0" * 64]:
        findings.append(f"the overlay's images are not read as «ref digest», newName winning over name and a trailing comment cut (got {lines})")

code = "\n".join(l for l in stage.splitlines() if not l.lstrip().startswith("//"))
if not re.search(r'git clone --quiet --depth 1 "\$\{REPO_URL\}"', code):
    findings.append("the apps stage does not clone each repo shallow from REPO_URL")
if re.search(r"\bgit\s+(push|commit)\b", code):
    findings.append("the apps stage pushes or commits: the watch only READS the tenants' repos")
if "$GH_TOKEN" not in code or re.search(r'https://[^"\s]*\$\{?GH_TOKEN', code):
    findings.append("the token is not handed to git through the credential helper (it would land in argv or a URL)")
if not re.search(r"sha256:0\{64\}", code):
    findings.append("a never-built app (64 zeros) would be scanned as if it ran")
if "kind: 'app'" not in code:
    findings.append("the apps found are not added to the watch's targets as KIND=app")
serving = src[src.index("stage('serving')"):src.index("stage('upstream')")]
if not re.search(r"pullAndScan\(\"\$\{env\.REGISTRY\}/\$\{dst\}\"\.toString\(\), t\.kind != 'base'", serving):
    findings.append("the serving stage does not scan mirrors and apps with the mirror's exceptions (only a base we own has none): an app re-reports what its base has excused")
app = serving.split("if (t.kind == 'app') {", 1)[1] if "if (t.kind == 'app') {" in serving else ""
if not app:
    findings.append("the serving stage has no second pass for apps: the mirror's exceptions would excuse the app's OWN layers")
else:
    if not re.search(r"pullAndScan\([^\n]*, false, \"\$\{n\}\.full\"", app):
        findings.append("an app is not scanned a second time WITHOUT the exceptions: its own layers could be excused by a base's measurement")
    if "crane config \"$ref\"" not in app or "$APP_FROMS" not in app:
        findings.append("the base's layers are not read from the app's FROMs")
    if not re.search(r"sh image-watch/ledger\.sh --inherit \"ledger-in/\$N_SCAN\.txt\" \"ledger-in/\$N_SCAN\.full\"", app):
        findings.append("the two scans of an app are not merged by ledger.sh --inherit")
if not re.search(r"if \(t\.unreadable\)", serving):
    findings.append("a repo that could not be cloned is scanned anyway instead of left unmeasured")
ledger = src[src.index("stage('ledger')"):src.index("stage('publish')")]
if "(t.kind == 'app')" not in ledger or "a build of ${t.slug}" not in ledger:
    findings.append("the books do not name the app's repo as who fixes an app's finding")

if "NOT watched" not in stage or not re.search(r"if \(f\.size\(\) != 2\) \{\s*\n(\s*//.*\n)*\s*echo \"NOTICE:", stage):
    findings.append("a line of the overlay the stage cannot read is skipped without a word: an app absent from the books reads like a clean one")

# THE WHOLE FILE, not only this stage: a pipeline from SCM runs in the
# Groovy sandbox, and this Jenkinsfile was written with plain `for` loops
# from its first day. What was added on 2026-10-02 used closure methods,
# List.indexOf, a split with a limit and a default parameter — none of
# them ever run on this job. None of them is needed, so none stays: what
# the first run of the series meets is what already ran.
whole = "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("//"))
for pat, what in ((r"\.\s*(find|findAll|findResult|any|every|each|collect|inject|sort|groupBy)\s*\{", "a closure-taking collection method"),
                  (r"TARGETS\.indexOf\(", "TARGETS.indexOf()"),
                  (r"\.split\([^()]*,\s*-?[0-9]+\)", "a split with a limit"),
                  (r"^def \w+\([^)]*=[^)]*\)\s*\{", "a default parameter")):
    hit = re.search(pat, whole, re.M)
    if hit:
        findings.append(f"image-watch uses {what} ({hit.group(0).strip()[:40]}): never run under this job's sandbox — write it as the rest of the file does")

for x in findings:
    print(x)
print("SCOPE: the apps stage's two shell blocks run over 2 fixture contracts and 1 overlay (name, newName, 64 zeros); clone, push, token, serving and books read")
