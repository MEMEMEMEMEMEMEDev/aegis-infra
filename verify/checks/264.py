"""Check 264 — `aegis app apply` plants the skeleton LAST, and `app new` tells the steps in the order that works.

MEASURED 2026-09-30 on alpha-arch, mounting the Astro portfolio:
- `app apply` created the repo, pushed the skeleton, registered the deploy
  key, and only then the webhook. The skeleton's push reached GitHub with
  nobody to tell Jenkins: the multibranch never scanned and the first
  build never started. Only the next push built anything.
- `app new` printed «2. app apply --check, 3. commit+push of platform/»:
  the check ran before the push and could only say COULD NOT EVALUATE —
  the deploy key's Secret and the Jenkins job are born from that push.

The check LOADS libexec/aegis-app with GitHub, the keys and `aegis webhook`
replaced by recorders, runs `app apply` on one contract, and requires the
skeleton's push to come after the webhook. It reads the printed next
steps for their order.
"""
import importlib.machinery
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
APP = os.path.join(ROOT, "libexec", "aegis-app")
findings = []

with tempfile.TemporaryDirectory() as tmp:
    os.environ["AEGIS_ROOT"] = ROOT
    os.environ["PLATFORM_DIR"] = os.path.join(tmp, "platform")
    os.makedirs(os.path.join(tmp, "platform", "orgs"))
    loader = importlib.machinery.SourceFileLoader("aegis_app_264", APP)
    spec = importlib.util.spec_from_loader("aegis_app_264", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)

    calls = []
    staging = os.path.join(tmp, "stage")
    os.makedirs(staging)
    open(os.path.join(staging, "Containerfile"), "w").close()
    contract = {"organizacion": "demo", "servicios": []}
    url = "git@github.com:someone/demo-app.git"

    class Gen:
        def repos_of(self, c):
            return {url: "demo-app"}

    # gh's session too: apply asks `gh auth status` before any repo, and
    # a machine with no session (the public CI, 2026-10-13) stopped there
    # with «calls: []» — the order was never reached, so never measured.
    m._gh = lambda *a, **k: subprocess.CompletedProcess(["gh", *a], 0, "", "")
    m._contract = lambda arg: (os.path.join(tmp, "platform", "orgs", "demo.yaml"), contract)
    m._generator = lambda: Gen()
    m._repo_exists = lambda o, r: calls.append("exists?") or False
    m._create_repo = lambda o, r, org: calls.append("create repo")
    m._has_history = lambda o, r: False
    m._staging_for = lambda c, u: (staging, "")
    m._plant = lambda o, r, st: calls.append("plant skeleton")
    m._public_of = lambda name: "ssh-ed25519 AAAA"
    m._keys_of = lambda o, r: []
    m._register_key = lambda o, r, pub: calls.append("deploy key")

    def run_json(cmd, *args):
        calls.append(f"{cmd} {' '.join(args)}".strip())
        return 0, {"steps": [{"step": "someone/demo-app", "state": "done"}]}
    m.cli.run_json = run_json

    saved = sys.argv
    sys.argv = ["aegis-app", "apply", "demo"]
    out = open(os.devnull, "w")
    so = sys.stdout
    sys.stdout = out
    try:
        rc = m.main()
    except SystemExit as e:
        rc = e.code
    finally:
        sys.stdout = so
        sys.argv = saved

    order = [c for c in calls if c != "exists?"]
    if "plant skeleton" not in order or not any(c.startswith("webhook") for c in order):
        findings.append(f"app apply did not both plant the skeleton and set the webhook (calls: {order})")
    else:
        hook = next(i for i, c in enumerate(order) if c.startswith("webhook"))
        plant = order.index("plant skeleton")
        if plant < hook:
            findings.append(f"app apply plants the skeleton BEFORE the webhook exists ({order}): its push tells nobody and the first build never starts (alpha-arch)")
        if "deploy key" in order and order.index("deploy key") > plant:
            findings.append(f"the deploy key is registered after the first build was triggered ({order}): ArgoCD cannot read the repo it deploys")

    # the printed next steps
    with open(APP, encoding="utf-8") as f:
        src = f.read()
    block = src[src.find('next steps, IN ORDER'):]
    block = block[:block.find("return 0")]
    i_push = block.find("commit+push of platform/")
    i_apply = block.find("cli.cmd('app apply')")
    i_edge = block.find("tofu apply of the edge")
    if -1 in (i_push, i_apply, i_edge):
        findings.append("app new's next steps no longer name the push, the edge and app apply")
    elif not (i_push < i_edge < i_apply):
        findings.append("app new's next steps put app apply before the push or the edge: its check can only answer «could not evaluate»")

print("SCOPE: app apply run with GitHub, keys and aegis webhook recorded (call order); app new's next steps read")
for x in findings:
    print(x)
