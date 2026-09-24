"""Check 236 — a Kyverno restart owed for the CA is measured, not remembered.

2026-09-24, second cloud VM: the first phase-80 run injected the registry
CA into Kyverno's values (23:51) and died in mirror-images before the
restart block; the later runs found the CA already in git, the flag
«injected on THIS run» stayed false, and the admission controller
(started 23:40, the CA mounted by subPath) kept a file without the aegis
CA. It fell back to plain HTTP against the registry and denied the signed
canary for fifteen minutes.

Driven: the measurement is lifted out of the phase and run against a
fake kubectl answering four cluster shapes.
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
m = re.search(r"^_kyverno_ca_restart_owed\(\) \{.*?^\}", src, re.M | re.S)
if not m:
    print("phase 80 does not measure whether a Kyverno controller holds a CA older than the one "
          "it mounts: a restart owed by a run that died is never paid")
    sys.exit(0)
fn = m.group(0)

i_def = m.start()
i_call = src.find('KYV_OWED="$(_kyverno_ca_restart_owed)"')
if i_call < 0:
    findings.append("the measurement is defined and never taken before the restart decision")
cond = re.search(r'^if \[\[ "\$CA_INJECTED_THIS_RUN" == "true" \|\| -n "\$KYV_OWED" \]\]; then', src, re.M)
if not cond:
    findings.append("the restart is not decided by the measurement: only the run that injected "
                    "the CA restarts Kyverno, and it may die before it gets there")
g = re.search(r'gate\s+"kyverno-ca-cargada"\s+_kyverno_ca_loaded', src)
if not g:
    findings.append("no gate proves afterwards that no Kyverno controller still holds a stale CA")
elif cond and g.start() < cond.start():
    findings.append("the kyverno-ca-cargada gate runs before the restart it is meant to prove")
w = re.search(r'gate\s+"kyverno-webhook-sirviendo"', src)
if g and w and w.start() < g.start():
    findings.append("the policy sync is reached before the CA is proven loaded")

# ── driven: a fake kubectl, four shapes ────────────────────────────────
FAKE = r'''#!/usr/bin/env bash
# args joined; answers by shape
a="$*"
case "$a" in
  "-n kyverno get deploy -o name") printf '%s\n' $DEPLOYS ;;
  "-n kyverno get deployment.apps/adm -o json")
     printf '{"spec":{"selector":{"matchLabels":{"c":"adm"}},"template":{"spec":{"volumes":[{"name":"ca","configMap":{"name":"adm-ca-certificates"}}]}}}}' ;;
  "-n kyverno get deployment.apps/cln -o json")
     printf '{"spec":{"selector":{"matchLabels":{"c":"cln"}},"template":{"spec":{"volumes":[]}}}}' ;;
  "-n kyverno get cm adm-ca-certificates --show-managed-fields -o json")
     printf '{"metadata":{"managedFields":[{"time":"2026-09-23T23:40:54Z","fieldsV1":{"f:metadata":{}}},{"time":"%s","fieldsV1":{"f:data":{}}}]}}' "$CM_WRITTEN" ;;
  "-n kyverno get pods -l c=adm --field-selector=status.phase=Running -o json")
     printf '{"items":[%s]}' "$PODS" ;;
  *) echo "fake kubectl: unexpected: $a" >&2; exit 9 ;;
esac
'''
SHAPES = [
    ("the admission controller started before its CA was written (the 2026-09-24 cluster)",
     "deployment.apps/adm deployment.apps/cln", "2026-09-23T23:51:37Z",
     '{"status":{"startTime":"2026-09-23T23:40:56Z"}}', ["deployment.apps/adm"]),
    ("the controller restarted after the CA landed",
     "deployment.apps/adm", "2026-09-23T23:51:37Z",
     '{"status":{"startTime":"2026-09-24T04:50:00Z"}}', []),
    ("a rollout halfway: one new pod, one pod still from before the CA",
     "deployment.apps/adm", "2026-09-23T23:51:37Z",
     '{"status":{"startTime":"2026-09-24T04:50:00Z"}},{"status":{"startTime":"2026-09-23T23:40:56Z"}}',
     ["deployment.apps/adm"]),
    ("a controller that mounts no CA at all",
     "deployment.apps/cln", "2026-09-23T23:51:37Z", "", []),
]
with tempfile.TemporaryDirectory() as td:
    k = os.path.join(td, "kubectl")
    open(k, "w").write(FAKE)
    os.chmod(k, os.stat(k).st_mode | stat.S_IEXEC)
    for name, deploys, written, pods, want in SHAPES:
        env = {**os.environ, "PATH": td + os.pathsep + os.environ["PATH"],
               "DEPLOYS": deploys, "CM_WRITTEN": written, "PODS": pods}
        r = subprocess.run(["bash", "-c", fn + "\n_kyverno_ca_restart_owed"],
                           capture_output=True, text=True, env=env)
        driven += 1
        got = [l for l in r.stdout.splitlines() if l]
        if r.returncode != 0 or got != want:
            findings.append(f"with {name} the measurement said {got} (rc {r.returncode}"
                            f"{', ' + r.stderr.strip()[:120] if r.stderr.strip() else ''}), expected {want}")

for f in findings:
    print(f)
print(f"SCOPE: the restart decision, the gate after it, and the measurement driven {driven} times "
      "against a fake kubectl")
