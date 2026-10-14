"""Check 260 — a static front compiles in the pipeline, and the image build only copies it.

MEASURED 2026-09-28 on a user's instance (their H-08): an Astro site built with
the static template failed four builds of four — Astro printed «Complete!»
and kaniko died «permission denied» closing the build stage (Vite/esbuild
leave a process kaniko cannot snapshot). And 2026-09-30 on the Arch lab VM the
template could not even be instantiated: its build stage stood on
node:22.23.1-alpine, and the door retained that image (its bundled npm
carried eleven CVEs past their window).

Since then the front compiles in the pipeline's `compile` stage, with the
repo's own ci/compile.sh in aegis-ci-node, and the Containerfile only
COPYs dist/ onto the signed runtime. This check reads the template and the
tenant pipeline, and RUNS the template's ci/compile.sh on a copy of it
(when this machine has npm) to prove it leaves dist/ where the
Containerfile looks. What the run proves is ALSO read, comment-stripped:
the full teeth of 2026-10-12 ran on a lab VM with no npm, and a tooth
that only the run could see (the OUT_DIR move) did not bite there.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
APP = os.path.join(ROOT, "seed", "templates", "static", "repos", "app")
JF = os.path.join(ROOT, "seed", "platform", "docs", "protocols", "templates", "Jenkinsfile.app")
findings = []


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


cf = "\n".join(l for l in read(os.path.join(APP, "Containerfile")).splitlines() if not l.lstrip().startswith("#"))
froms = re.findall(r"^\s*FROM\s+(\S+)", cf, re.M)
if len(froms) != 1:
    findings.append(f"the static Containerfile has {len(froms)} FROM(s): a build stage is back, and with it the build image and Vite inside kaniko")
if re.search(r"^\s*RUN\b", cf, re.M):
    findings.append("the static Containerfile RUNs something: the runtime has no shell, and a compile inside the image build is H-08")
if not re.search(r"^\s*COPY\s+(--chown=\S+\s+)?dist/\s+\./public/", cf, re.M):
    findings.append("the static Containerfile does not COPY dist/ into ./public/: what ci/compile.sh wrote is not what is served")

cs_path = os.path.join(APP, "ci", "compile.sh")
if not os.path.isfile(cs_path):
    findings.append("the static template ships no ci/compile.sh: its repo would never compile")
else:
    # comment-stripped: the script's own prose says «`npm ci` and NOT `npm
    # install`», and a read of the raw file found the promise there
    cs = "\n".join(l for l in read(cs_path).splitlines() if not l.lstrip().startswith("#"))
    if not re.search(r"^\s*npm ci\b", cs, re.M):
        findings.append("ci/compile.sh does not install with `npm ci`: the lock stops being what is built")
    # read as well as run: a machine without npm (an aegis host, a lab VM)
    # never runs it, and the move is what an Angular front depends on
    if not re.search(r'^\s*mv\s+"\$OUT_DIR"\s+dist\s*$', cs, re.M):
        findings.append("ci/compile.sh does not move an OUT_DIR elsewhere into dist/: Angular's dist/<project>/browser "
                        "would never reach the one path the Containerfile copies")

di = [l.strip() for l in read(os.path.join(APP, ".dockerignore")).splitlines() if l.strip() and not l.startswith("#")]
if not di or di[0] != "*" or "!dist" not in di or "!serve.mjs" not in di:
    findings.append(f".dockerignore is not the allowlist `*`, `!serve.mjs`, `!dist`: {di}")

jf = "\n".join(l for l in read(JF).splitlines() if not l.lstrip().startswith("//"))
comp = re.search(r"stage\('compile'\)\s*\{(.*?)\n    stage\('", jf, re.S)
b = jf.find("stage('build')")
if not comp:
    findings.append("Jenkinsfile.app has no stage('compile'): a front can only compile inside kaniko")
else:
    body = comp.group(1)
    if comp.start() > b:
        findings.append("the compile stage runs after the image build: kaniko copies a dist/ that does not exist yet")
    if not re.search(r"fileExists\('ci/compile\.sh'\)", body) or "SKIP_BUILD" not in body:
        findings.append("the compile stage is not gated by the repo's ci/compile.sh and by SKIP_BUILD: a Go service would try to npm")
    if not re.search(r"container\('node'\)\s*\{.*?sh ci/compile\.sh", body, re.S):
        findings.append("the compile stage does not run `sh ci/compile.sh` in the node container (aegis-ci-node)")

if shutil.which("npm") and os.path.isfile(cs_path):
    with tempfile.TemporaryDirectory() as tmp:
        work = os.path.join(tmp, "app")
        shutil.copytree(APP, work)
        for dp, dn, fn in os.walk(work):
            for f in fn:
                fp = os.path.join(dp, f)
                try:
                    t = read(fp)
                except UnicodeDecodeError:
                    continue
                if "__ORG__" in t:
                    with open(fp, "w", encoding="utf-8") as fh:
                        fh.write(t.replace("__ORG__", "check260"))
        env = dict(os.environ, npm_config_cache=os.path.join(tmp, "npm-cache"), npm_config_update_notifier="false")
        p = subprocess.run(["sh", "ci/compile.sh"], cwd=work, capture_output=True, text=True, timeout=300, env=env)
        if p.returncode != 0:
            findings.append(f"the template's ci/compile.sh fails on the template itself (rc {p.returncode}): {(p.stderr or p.stdout).strip()[-160:]}")
        elif not os.path.isfile(os.path.join(work, "dist", "index.html")):
            findings.append("the template's ci/compile.sh ran and left no dist/index.html for the Containerfile to copy")
        # an OUT_DIR elsewhere still lands in dist/
        env2 = dict(env, BUILD_CMD="mkdir -p build/www && cp -r src/. build/www/", OUT_DIR="build/www")
        p = subprocess.run(["sh", "ci/compile.sh"], cwd=work, capture_output=True, text=True, timeout=300, env=env2)
        if p.returncode != 0 or not os.path.isfile(os.path.join(work, "dist", "index.html")):
            findings.append(f"with OUT_DIR elsewhere (Angular's dist/<p>/browser) the result does not land in dist/ (rc {p.returncode})")
    ran = "ci/compile.sh RUN on a copy of the template (twice: its own build, and an OUT_DIR elsewhere)"
else:
    ran = "ci/compile.sh read only (no npm on this machine)"

print(f"SCOPE: the static template's Containerfile, .dockerignore and ci/compile.sh; Jenkinsfile.app's compile stage; {ran}")
for x in findings:
    print(x)
