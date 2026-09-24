"""Check 237 — a canary sync that died on the signed digest is fired again.

2026-09-24, second cloud VM: ArgoCD's auto-sync of the canary revision
carrying the signed digest ran while Kyverno could not yet read
signatures, and was denied. Kyverno was repaired minutes later, and the
canary gate waited fifteen minutes for a sync that never came: ArgoCD
does not re-attempt an automated sync of the same revision after it
failed. The phase has to notice that exact failure and sync again, after
the policy is live and before it waits.

Driven: the condition is lifted out of the phase and asked about three
Application shapes through a fake kubectl.
"""
import os
import re
import stat
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
PH = os.path.join(ROOT, "init", "phases", "80-supply-chain.sh")
findings = []
driven = 0

raw = open(PH, encoding="utf-8").read()
src = "\n".join(l for l in raw.splitlines() if not re.match(r"^\s*#", l))
m = re.search(r"^_canary_sync_stuck_on_digest\(\) \{.*?^\}", src, re.M | re.S)
if not m:
    print("phase 80 never asks whether the canary's last sync died refusing the signed digest: "
          "the gate waits for a sync ArgoCD will not retry")
    sys.exit(0)
fn = m.group(0)

use = re.search(r"^if _canary_sync_stuck_on_digest; then\n(.*?)^fi", src, re.M | re.S)
if not use or not re.search(r"^\s*argo_sync hello-aegis\b", use.group(1), re.M):
    findings.append("the stuck sync is detected and nothing syncs the canary again")
pos = {k: (re.search(p, src, re.M).start() if re.search(p, src, re.M) else -1) for k, p in {
    "policy": r'gate\s+"policy-ready"',
    "resync": r"^if _canary_sync_stuck_on_digest; then",
    "wait": r'gate_diag\s+"canary-pineado-a-digest"',
}.items()}
if use and (pos["policy"] < 0 or pos["resync"] < pos["policy"]):
    findings.append("the canary is re-synced before the policy is live: the same denial again")
if use and pos["wait"] >= 0 and pos["wait"] < pos["resync"]:
    findings.append("the re-sync comes after the canary gate: the fifteen minutes are spent first")

D = "sha256:86a5d572df8eb6fce1e84482e0ff1beecd4ef001802e48ecb68a0530dc692a6e"
FAKE = '#!/usr/bin/env bash\nprintf %s "$APP_JSON"\n'
SHAPES = [
    ("a failed sync that was refusing THIS digest (2026-09-24)",
     '{"status":{"operationState":{"phase":"Failed","message":"denied: failed to verify image '
     'registry:5000/hello-aegis@' + D + ': GET http://registry:5000/v2/: 400"}}}', 0),
    ("a failed sync over ANOTHER image",
     '{"status":{"operationState":{"phase":"Failed","message":"denied: hello-aegis@sha256:1111"}}}', 1),
    ("a sync still Running over the signed digest (re-firing it would fight it)",
     '{"status":{"operationState":{"phase":"Running","message":"waiting for healthy state of apps/Deployment/hello-aegis '
     '(hello-aegis@' + D + ')"}}}', 1),
    ("a sync that succeeded",
     '{"status":{"operationState":{"phase":"Succeeded","message":"successfully synced"}}}', 1),
    ("an Application that cannot be read", "", 1),
]
with tempfile.TemporaryDirectory() as td:
    k = os.path.join(td, "kubectl")
    open(k, "w").write(FAKE)
    os.chmod(k, os.stat(k).st_mode | stat.S_IEXEC)
    for name, app, want in SHAPES:
        env = {**os.environ, "PATH": td + os.pathsep + os.environ["PATH"], "APP_JSON": app, "DIGEST": D}
        r = subprocess.run(["bash", "-c", fn + "\n_canary_sync_stuck_on_digest"],
                           capture_output=True, text=True, env=env)
        driven += 1
        got = 0 if r.returncode == 0 else 1
        if got != want:
            findings.append(f"with {name} the condition answered {'stuck' if got == 0 else 'not stuck'}, "
                            f"expected {'stuck' if want == 0 else 'not stuck'}")

for f in findings:
    print(f)
print(f"SCOPE: the re-sync's place between the policy and the canary gate, and the condition driven "
      f"{driven} times")
