"""Check 230 — the valve's probe can say YES, and it can still say NO.

2026-09-22, the first cloud instance: phase 20 restarted k3s to apply the
node reservation and then asked `kubectl get --raw=/readyz`. The user's
kubeconfig is written further down in the same phase, so up there kubectl
talks to localhost:8080 and refuses however healthy the cluster is. The
API had been up for three minutes; the valve withdrew a reservation that
was never the problem and the phase died.

Driven: the probe is lifted out of the phase and run against a fake
`sudo`/`kubectl` in three shapes — a healthy cluster with no user
kubeconfig, a cluster that is really down, and a machine where sudo -n is
refused but the user's kubeconfig works.
"""
import os
import re
import stat
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
PH = os.path.join(ROOT, "init", "phases", "20-k3s.sh")
findings = []
driven = 0

src = open(PH, encoding="utf-8").read()
m = re.search(r"^_k3s_api_answers\(\) \{.*?^\}", src, re.M | re.S)
if not m:
    print("phase 20 no longer defines _k3s_api_answers: the valve has no probe to measure")
    sys.exit(0)
probe = m.group(0)
body = "\n".join(l for l in probe.splitlines() if not re.match(r"^\s*#", l))

# ── the probe must not depend on what this phase writes LATER ────────
i_probe = src.index("_k3s_api_answers() {")
i_kube = src.find('"$HOME/.kube/config"')
if 0 <= i_kube < i_probe:
    pass   # the copy happens first: then a bare kubectl would be fine
elif "/etc/rancher/k3s/k3s.yaml" not in body:
    findings.append("the probe runs before this phase writes ~/.kube/config and does not name k3s's "
                    "own kubeconfig: up there kubectl answers «connection refused» on a healthy "
                    "cluster, and the valve withdraws the reservation every time")

SHAPES = [
    ("a healthy cluster and no user kubeconfig", True, False, 0),
    ("a cluster that is really down", False, False, 1),
    ("sudo -n refused, the user's kubeconfig working", False, True, 0),
]
for name, k3s_ok, user_ok, want in SHAPES:
    with tempfile.TemporaryDirectory() as td:
        with open(os.path.join(td, "sudo"), "w") as f:
            # sudo -n works only where the k3s kubeconfig is the answer
            f.write("#!/bin/sh\n" + ('shift; exec "$@"\n' if k3s_ok else "exit 1\n"))
        with open(os.path.join(td, "kubectl"), "w") as f:
            f.write("#!/bin/sh\n"
                    'if [ "$KUBECONFIG" = "/etc/rancher/k3s/k3s.yaml" ]; then\n'
                    + ("  echo ok\n  exit 0\n" if k3s_ok else "  exit 1\n") +
                    "fi\n"
                    + ("echo ok\nexit 0\n" if user_ok else "exit 1\n"))
        for x in ("sudo", "kubectl"):
            os.chmod(os.path.join(td, x), stat.S_IRWXU)
        r = subprocess.run(["bash", "-c", f"{probe}\n_k3s_api_answers"],
                           capture_output=True, text=True,
                           env={**os.environ, "PATH": td + ":" + os.environ.get("PATH", "")})
        driven += 1
        if r.returncode != want:
            findings.append(f"with {name} the probe answered rc {r.returncode}, expected {want}"
                            + (": the valve fires on a cluster that is fine and withdraws the "
                               "reservation" if want == 0 else
                               ": a valve that cannot say NO is not a safety net"))

for f in findings:
    print(f)
print(f"SCOPE: the probe lifted out of phase 20 and driven in {driven} shapes")
