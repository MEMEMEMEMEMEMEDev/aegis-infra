"""Check 265 — `aegis app rebase` brings an app's Jenkinsfile to the pipeline the platform derives.

MEASURED 2026-09-30 on alpha-arch: the platform changed the tenant scan
(judge the image's own layers; the base's findings are inherited) and the
portfolio kept running the old pipeline — `app apply` plants a Jenkinsfile
once, into an empty repo, and never again. The new one waited in the
staging area until somebody copied it into the app's repo by hand.

`app rebase <org>` — the verb that already puts an app's repos on THIS
installation (its FROMs) and leaves the push to a person — now also brings
each repo's Jenkinsfile to the derived one. The check LOADS
libexec/aegis-app with the checkout and the staging replaced by
directories it controls, and runs rebase dry and for real.
"""
import importlib.machinery
import importlib.util
import os
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
APP = os.path.join(ROOT, "libexec", "aegis-app")
findings = []

with tempfile.TemporaryDirectory() as tmp:
    os.environ["AEGIS_ROOT"] = ROOT
    os.environ["PLATFORM_DIR"] = os.path.join(tmp, "platform")
    os.makedirs(os.path.join(tmp, "platform", "orgs"))
    loader = importlib.machinery.SourceFileLoader("aegis_app_265", APP)
    spec = importlib.util.spec_from_loader("aegis_app_265", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)

    repo_dir = os.path.join(tmp, "checkout")
    stage = os.path.join(tmp, "stage")
    os.makedirs(repo_dir)
    os.makedirs(stage)
    with open(os.path.join(stage, "Jenkinsfile"), "w") as f:
        f.write("// the pipeline this platform derives (own layers judged)\n")
    contract = {"organizacion": "demo", "servicios": []}
    url = "git@github.com:someone/demo-app.git"

    class Gen:
        def repos_of(self, c):
            return {url: "demo-app"}

    m._contract = lambda arg: (os.path.join(tmp, "platform", "orgs", "demo.yaml"), contract)
    m._generator = lambda: Gen()
    m._checkout = lambda org, owner, repo, write: (repo_dir, False)
    m._staging_for = lambda c, u: (stage, "")
    m._containerfiles = lambda root: []

    def rebase(write):
        tot = {"already": 0, "done": 0, "would": 0, "not_evaluable": 0}
        so = sys.stdout
        sys.stdout = open(os.devnull, "w")
        try:
            m.rebase("demo", write, tot)
        finally:
            sys.stdout = so
        return tot

    old = "// the pipeline the repo was planted with (the whole image judged)\n"
    with open(os.path.join(repo_dir, "Jenkinsfile"), "w") as f:
        f.write(old)
    tot = rebase(False)
    if open(os.path.join(repo_dir, "Jenkinsfile")).read() != old:
        findings.append("rebase --check wrote the Jenkinsfile: a dry run touched the app's repo")
    if tot["would"] < 1:
        findings.append("rebase --check does not say the Jenkinsfile is behind the platform's")
    tot = rebase(True)
    if open(os.path.join(repo_dir, "Jenkinsfile")).read() != open(os.path.join(stage, "Jenkinsfile")).read():
        findings.append("rebase does not bring the app's Jenkinsfile to the derived one: the portfolio kept the old scan (alpha-arch)")
    elif tot["done"] < 1:
        findings.append("rebase changed the Jenkinsfile without saying so")
    tot = rebase(True)
    if tot["done"] != 0 or tot["already"] < 1:
        findings.append(f"a second rebase over an up-to-date Jenkinsfile is not a no-op ({tot})")

print("SCOPE: app rebase run over a controlled checkout and staging area: dry, for real, and again")
for x in findings:
    print(x)
