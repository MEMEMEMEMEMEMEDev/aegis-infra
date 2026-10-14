"""Check 131 — a capacity nobody could measure is never reported as zero,
and what a plan costs is read from plans.yaml.

TWO GUARANTEES, and the first one is the product's whole thesis applied
to the one question an operator asks under pressure.

  1. BLIND IS NOT FULL. If the apiserver does not answer, «no room» and
     «I could not look» are the same sentence to anybody reading a
     screen, and they are opposite facts: one says stop, the other says
     go find out. A command that answered zero there would refuse an
     organization that fits, on a machine that was never asked.

  2. WHAT A PLAN COSTS IS NOT WRITTEN HERE. plans.yaml is where the
     numbers live —«los números nunca van en el contrato», and they do
     not go in a command either— and a copy of them inside aegis-capacity
     would keep answering confidently after somebody adjusts a plan for
     every organization at once.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

import yaml

ROOT = sys.argv[1]
CAP = os.path.join(ROOT, "libexec", "aegis-capacity")
PLANS = os.path.join(ROOT, "seed", "platform", "plans.yaml")

if not os.path.isfile(CAP):
    print("SCOPE: there is no capacity command")
    sys.exit(0)


def code(path):
    return "\n".join(l for l in open(path, encoding="utf-8").read().splitlines()
                     if not l.lstrip().startswith("#"))


# ── 1 · blind, behaviourally ─────────────────────────────────────────
# KUBECONFIG at /dev/null: kubectl starts, finds no cluster and fails.
# Nothing is created, nothing is contacted. The instance is a sandbox
# of this check's own, with the SEED's plans.yaml in it: without one,
# the `capacity:plans` step comes out not-evaluable on its own and a
# command that answered zeros for everything else would still pass as
# «declared not-evaluable» (the tooth that plants the zeros did not
# bite on a clean clone; measured 2026-10-14, review of 2026-10-13,
# 4B-7). The instance's variables never reach it (the 286 pattern).
env = {k: v for k, v in os.environ.items()
       if not (k.startswith("AEGIS_") or k in ("PLATFORM_DIR", "SOPS_AGE_KEY_FILE", "AGE_PUBLIC"))}
sandbox = tempfile.mkdtemp(prefix="aegis-131.")
os.makedirs(os.path.join(sandbox, "platform"))
shutil.copy(PLANS, os.path.join(sandbox, "platform", "plans.yaml"))
env["AEGIS_ROOT"] = ROOT
env["AEGIS_HOME"] = sandbox
env["HOME"] = sandbox
env["KUBECONFIG"] = "/dev/null"
run = subprocess.run([os.path.join(ROOT, "bin", "aegis"), "capacity", "show", "--json"],
                     capture_output=True, text=True, env=env)
shutil.rmtree(sandbox, ignore_errors=True)
blind_ok = False
try:
    doc = json.loads(run.stdout)
except ValueError:
    print(f"with no cluster, `aegis capacity --json` returned no readable document "
          f"(rc {run.returncode}): a console asking it would have nothing to draw and "
          f"no reason why")
    doc = None

if doc is not None:
    states = {s.get("state") for s in doc.get("steps") or []}
    if doc.get("rc") != 2:
        print(f"with no cluster the command exits {doc.get('rc')} and the contract says 2 "
              f"means «could not evaluate»: the round and the console both read that number")
    if "not-evaluable" not in states:
        print("with no cluster no step is filed as `not-evaluable`: the screen would show "
              "something other than «I could not look»")
    else:
        blind_ok = True
    for step in doc.get("steps") or []:
        # a capacity «measured» as zero by a command nobody could ask is
        # the same lie one step earlier
        if step.get("step", "").startswith("capacity:") and step.get("state") == "already" \
                and step.get("allocatable") == 0:
            print(f"with no cluster the command files {step['step']} as measured (already) with "
                  f"allocatable 0: a blind read reported as a full machine")
        if step.get("step", "").startswith("fits:") and step.get("room") == 0:
            print(f"with no cluster the command still answers {step['step']} with room 0: "
                  f"«no room» and «I could not look» are the same sentence on a screen and "
                  f"opposite facts — this one would refuse an organization that fits")

# ── 2 · the plans are read, not written ──────────────────────────────
src = code(CAP)
try:
    names = sorted((yaml.safe_load(open(PLANS, encoding="utf-8")) or {}).get("cuota") or {})
except OSError:
    names = []
for name in names:
    if name in src:
        print(f"aegis-capacity names the plan {name!r} in its own source: the numbers live "
              f"in plans.yaml and are readjusted for every organization at once, so a copy "
              f"here goes on answering confidently after they move")
if "plans.yaml" not in src and "PLANS" not in src:
    print("aegis-capacity does not read plans.yaml at all: whatever it compares against "
          "came from somewhere nobody maintains")

print(f"SCOPE: blindness exercised against a dead kubeconfig (declared not-evaluable: "
      f"{blind_ok}), {len(names)} plan name(s) checked against the source")
