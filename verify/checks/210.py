"""Check 210 — the CI's pod templates agree, everywhere and with their owner.

The same image is written by hand in six Jenkinsfiles. Nothing joins
them: bumping the agent means editing six lines in one commit, and a
bump that edits five leaves a pipeline building on a version nobody
chose — which fails, if it fails at all, weeks later and somewhere
else.

Two rules, both derived:
  1. every Jenkinsfile that names an image names the SAME version of it;
  2. an image this instance builds is pinned in the Jenkinsfiles at the
     tag its own Containerfile or its pin declares — `aegis-ci-cosign`
     against `userland_pins.cosign`, `aegis-ci-crane` against the FROM
     of ci-images/crane.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
ROOT = sys.argv[1]
SEED = os.path.join(ROOT, "seed", "platform")
findings = []

try:
    from aegis import pins
except Exception as e:                                    # noqa: BLE001
    print(f"lib/aegis/pins.py cannot be imported ({e}): the pod templates were not compared")
    sys.exit(0)

if not os.path.isdir(SEED):
    print("SCOPE: there is no seed platform")
    sys.exit(0)

all_pins = pins.read(ROOT)
jf = [p for p in all_pins.values() if p.cls == "jenkinsfile"]
if not jf:
    print("no Jenkinsfile of the seed pins an image: either the CI stopped declaring its pod "
          "templates or the reader that finds them is broken")
    print("SCOPE: nothing to compare")
    sys.exit(0)

# 1 · one version per image, however many files name it
for p in jf:
    if p.extra.get("conflicto"):
        where = ", ".join(f"{f}:{n}" for f, n in p.where)
        findings.append(f"{p.name} is pinned at {p.current} and also at "
                        f"{', '.join(sorted(set(p.extra['conflicto'])))} across {where}: a bump "
                        f"that edits some of the copies leaves a pipeline building on a version "
                        f"nobody chose")

# 2 · what this instance builds is pinned at what it builds
owners = {}
for p in all_pins.values():
    if p.cls == "containerfile":
        owners[p.name.rsplit("/", 1)[-1]] = (p.current, p.where[0])
    if p.cls == "userland":
        owners[p.name] = (p.current, p.where[0])

for p in jf:
    short = p.name.rsplit("/", 1)[-1]
    if not short.startswith("aegis-ci-"):
        continue
    tool = short[len("aegis-ci-"):]
    owner = owners.get(tool)
    if not owner:
        continue
    want, where = owner
    if not want:
        continue
    if p.current.lstrip("v") != want.lstrip("v"):
        findings.append(f"{short} is pinned at {p.current} in the pod templates and its owner "
                        f"says {want} ({where[0]}:{where[1]}): the CI would run a version this "
                        f"instance does not build")

for f in findings:
    print(f)
print(f"SCOPE: {len(jf)} image(s) of the pod templates across "
      f"{len({w[0] for p in jf for w in p.where})} Jenkinsfile(s), "
      f"{sum(len(p.where) for p in jf)} location(s)")
