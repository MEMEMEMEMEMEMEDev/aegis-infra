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
import subprocess
import sys

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
# Nothing is created, nothing is contacted.
env = {k: v for k, v in os.environ.items() if not k.startswith("AEGIS_")}
env["AEGIS_ROOT"] = ROOT
env["KUBECONFIG"] = "/dev/null"
run = subprocess.run([os.path.join(ROOT, "bin", "aegis"), "capacity", "show", "--json"],
                     capture_output=True, text=True, env=env)
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
