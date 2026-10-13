"""Check 282 — phase 80 says why the canary keeps its public bases.

Measured on alpha-ubuntu, 2026-10-13: the door held golang and alpine back
(check 255's case), and phase 80 ended with «phase 80-supply-chain FAILED»
and not one word more. `_GOLANG="$(_canary_from golang)"` is a bare
assignment from a $() that fails, and under set -e that ends the phase on
that line — the else branch below it, the only line that says «the mirror
does not serve golang/alpine yet», could never run.

Driven: the block of phase 80 that repoints the canary's Containerfile,
cut from `_canary_from() {` to the `fi` of its warning, runs under
`set -euo pipefail` with a fake `aegis image from`, in three worlds:
  · the mirror does not declare golang → the phase goes on and warns;
  · it declares both, but the registry does not hold them (alpha-ubuntu)
    → the phase goes on and warns;
  · it serves both → the Containerfile is repointed, by digest.
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
findings = []
src = open(os.path.join(ROOT, "init", "phases", "80-supply-chain.sh"), encoding="utf-8").read()
m = re.search(r"^[ \t]*_canary_from\(\) \{.*?^[ \t]*log_warn \"the mirror does not serve golang/alpine yet[^\n]*\n[ \t]*fi\n",
              src, re.S | re.M)
if not m:
    print("phase 80 has no block that repoints the canary's bases and warns when it cannot")
    print("SCOPE: phase 80 read")
    sys.exit(0)
block = m.group(0)

FAKE_IMAGE = r'''#!/usr/bin/env bash
[[ "$1" == from ]] || exit 2
case "$MODE" in
  serves) echo "FROM registry.registry-system.svc.cluster.local:5000/${2%%:*}@sha256:abc" ;;
  *)      echo "$2 is not in the internal registry" >&2; exit 1 ;;
esac
'''
CONTAINERFILE = "FROM docker.io/library/golang:1.26-alpine AS build\nRUN true\nFROM docker.io/library/alpine:3.21\n"

with tempfile.TemporaryDirectory() as tmp:
    root = os.path.join(tmp, "root")
    os.makedirs(os.path.join(root, "libexec"))
    with open(os.path.join(root, "libexec", "aegis-image"), "w") as f:
        f.write(FAKE_IMAGE)
    os.chmod(os.path.join(root, "libexec", "aegis-image"), 0o755)
    plat = os.path.join(tmp, "platform")
    os.makedirs(os.path.join(plat, "mirror-images"))
    canary = os.path.join(tmp, "canary")
    os.makedirs(os.path.join(canary, "app"))
    script = os.path.join(tmp, "block.sh")
    with open(script, "w") as f:
        f.write("set -euo pipefail\n"
                "log_ok() { echo \"OK $*\" >&2; }\nlog_warn() { echo \"WARN $*\" >&2; }\n"
                "run_cmd() { \"$@\"; }\n" + block + "\necho REACHED\n")

    def world(name, images, mode):
        with open(os.path.join(plat, "mirror-images", "images.txt"), "w") as f:
            f.write(images)
        cf = os.path.join(canary, "app", "Containerfile")
        with open(cf, "w") as f:
            f.write(CONTAINERFILE)
        env = dict(os.environ, AEGIS_ROOT=root, PLATFORM_DIR=plat, CANARY_TMP=canary, MODE=mode)
        p = subprocess.run(["bash", script], capture_output=True, text=True, env=env, timeout=30)
        return p, open(cf).read()

    declared = ("public.ecr.aws/docker/library/golang:1.26.6-alpine golang:1.26.6-alpine\n"
                "public.ecr.aws/docker/library/alpine:3.21 alpine:3.21\n")
    for name, images, mode in (("the mirror does not declare golang", "# nothing\nx/redis:8 redis:8\n", "serves"),
                               ("the registry does not hold golang/alpine (alpha-ubuntu, 2026-10-13)", declared, "absent")):
        p, cf = world(name, images, mode)
        if p.returncode != 0 or "REACHED" not in p.stdout:
            findings.append(f"{name}: phase 80 ends there (rc {p.returncode}) before saying why — "
                            f"the warning about the mirror never prints")
        elif "WARN the mirror does not serve golang/alpine yet" not in p.stderr:
            findings.append(f"{name}: phase 80 goes on without saying the canary keeps its public bases")
        if cf != CONTAINERFILE:
            findings.append(f"{name}: the Containerfile was rewritten with nothing to point at")
    p, cf = world("the mirror serves both", declared, "serves")
    if p.returncode != 0 or "golang@sha256:abc" not in cf or "alpine@sha256:abc" not in cf:
        findings.append(f"the mirror serves golang and alpine, and the canary's Containerfile is not repointed "
                        f"by digest (rc {p.returncode})")

for x in findings:
    print(x)
print("SCOPE: phase 80's canary repoint driven under set -euo pipefail in three worlds (undeclared, held at the door, served)")
