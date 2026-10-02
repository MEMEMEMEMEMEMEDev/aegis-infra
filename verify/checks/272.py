"""Check 272 — a node service is installed and tested in the pipeline.

2026-09-30, alpha-arch: the static template moved its compile out of the
image build (check 260) because its build stage stood on
node:22.23.1-alpine — an image that had to be mirrored before the template
could be instantiated, and that the door retained (its bundled npm carried
CVEs past their window). service-node stood on the same image. On
2026-10-02 it follows: ci/compile.sh runs `npm ci`, `npm test`,
`npm prune --omit=dev` and `mkdir -p node_modules` in the pipeline's
aegis-ci-node, and the Containerfile is one FROM, no RUN, three COPYs.

This sidecar reads the template and RUNS its ci/compile.sh on a copy
(when this machine has npm): green on the template, red with a broken
test, and node_modules present with an empty dependency tree.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
APP = os.path.join(ROOT, "seed", "templates", "service-node", "repos", "app")
findings = []


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def code(p):
    return "\n".join(l for l in read(p).splitlines() if not l.lstrip().startswith("#"))


cf = code(os.path.join(APP, "Containerfile"))
froms = re.findall(r"^\s*FROM\s+(\S+)", cf, re.M)
if froms != ["__FROM_NODE__"]:
    findings.append(f"the service-node Containerfile FROMs {froms}, not the one runtime __FROM_NODE__: a build stage is back")
if re.search(r"^\s*RUN\b", cf, re.M):
    findings.append("the service-node Containerfile RUNs something: the runtime has no shell, and npm inside the image build is the build stage again")
for what in ("node_modules ./node_modules", "src ./src"):
    if not re.search(r"^\s*COPY\s+(--chown=\S+\s+)?" + re.escape(what), cf, re.M):
        findings.append(f"the Containerfile does not COPY {what.split()[0]} from the workspace")

di = [l.strip() for l in read(os.path.join(APP, ".dockerignore")).splitlines() if l.strip() and not l.startswith("#")]
if not di or di[0] != "*" or not {"!node_modules", "!src", "!package.json", "!package-lock.json"} <= set(di):
    findings.append(f".dockerignore is not the allowlist `*` + the manifest, node_modules and src: {di}")
if "!tests" in di:
    findings.append("the tests travel into the image")

cs_path = os.path.join(APP, "ci", "compile.sh")
if not os.path.isfile(cs_path):
    findings.append("service-node ships no ci/compile.sh: the pipeline's compile stage skips it and nothing installs or tests")
else:
    cs = code(cs_path)
    order = [cs.find(s) for s in ("npm ci", "npm test", "npm prune --omit=dev", "mkdir -p node_modules")]
    if -1 in order or order != sorted(order):
        findings.append("ci/compile.sh does not run npm ci → npm test → npm prune --omit=dev → mkdir -p node_modules, in that order")

tpl = os.path.join(ROOT, "seed", "templates")
for dp, _dn, fn in os.walk(tpl):
    for f in fn:
        if f == "Containerfile" and "__FROM_NODE_BUILD__" in code(os.path.join(dp, f)):
            findings.append(f"{os.path.relpath(os.path.join(dp, f), ROOT)} still stands on __FROM_NODE_BUILD__")

ran = "ci/compile.sh read only (no npm on this machine)"
if shutil.which("npm") and os.path.isfile(cs_path):
    with tempfile.TemporaryDirectory() as tmp:
        work = os.path.join(tmp, "app")
        shutil.copytree(APP, work)
        for dp, _dn, fn in os.walk(work):
            for f in fn:
                fp = os.path.join(dp, f)
                try:
                    t = read(fp)
                except UnicodeDecodeError:
                    continue
                if "__ORG__" in t:
                    with open(fp, "w", encoding="utf-8") as fh:
                        fh.write(t.replace("__ORG__", "check272"))
        env = dict(os.environ, npm_config_cache=os.path.join(tmp, "npm-cache"), npm_config_update_notifier="false")
        p = subprocess.run(["sh", "ci/compile.sh"], cwd=work, capture_output=True, text=True, timeout=300, env=env)
        if p.returncode != 0:
            findings.append(f"the template's ci/compile.sh fails on the template itself (rc {p.returncode}): {(p.stderr or p.stdout).strip()[-160:]}")
        elif not os.path.isdir(os.path.join(work, "node_modules")):
            findings.append("with an empty dependency tree ci/compile.sh leaves no node_modules: the Containerfile's COPY aborts the build")
        t = os.path.join(work, "tests", "handle.test.js")
        with open(t, "a", encoding="utf-8") as fh:
            fh.write("\ntest('check 272 breaks this on purpose', () => { assert.equal(1, 2) })\n")
        p = subprocess.run(["sh", "ci/compile.sh"], cwd=work, capture_output=True, text=True, timeout=300, env=env)
        if p.returncode == 0:
            findings.append("a red test does not stop ci/compile.sh: an image would be built from a failing suite")
    ran = "ci/compile.sh RUN on a copy of the template (green, and with a test broken on purpose)"

print(f"SCOPE: service-node's Containerfile, .dockerignore and ci/compile.sh; every template's FROMs; {ran}")
for x in findings:
    print(x)
