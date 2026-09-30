"""Check 243 — the kernel that is running still has its modules after the
upgrade the product itself runs.

2026-09-24, lab-arch: `aegis preflight` runs pkg_update, which on Arch is
`pacman -Syu`; it moved linux-lts from 6.18.52 to 6.18.53. Arch keeps one
module tree per INSTALLED kernel and removes the old one with the old
package, so the kernel still running had nothing left to load:
`modprobe vxlan` said «not found in directory /lib/modules/6.18.52-1-lts»,
flannel exited («failed to create vxlan device: operation not
supported»), kube-proxy could not load xt_comment, k3s restarted 19 times
and phase 20 timed out at coredns. The preflight had said 29 OK. Debian
and Ubuntu keep the old tree, which is why five months of runs never saw
it.

THE PROPERTY, in three parts:
  1. lib/host.sh has the measure, and it decides by the module tree of
     the running kernel: DRIVEN here with a fixture tree, once with the
     release present (rc 0, nothing on stdout) and once with it gone
     (rc 1, the remedy on stderr, nothing on stdout).
  2. the preflight asks it AFTER its pkg_update, and a «gone» is a FAIL
     (bad), not a warning the summary lets through.
  3. phase 05 asks it AFTER its pkg_update as a GATE, so the init stops
     right there with the reason instead of at phase 20.
Comments are dropped before reading (a comment that names the function
is prose); the calls are read in command position.
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
LIB = os.path.join(ROOT, "lib", "host.sh")
PRE = os.path.join(ROOT, "libexec", "aegis-preflight")
P05 = os.path.join(ROOT, "init", "phases", "05-host.sh")
FN = "host_running_kernel_has_modules"
findings = []


def code_lines(path):
    """(lineno, text) of every line that is not a full-line comment."""
    with open(path, encoding="utf-8", errors="replace") as f:
        for n, ln in enumerate(f, 1):
            if re.match(r"^\s*#", ln):
                continue
            yield n, ln.rstrip("\n")


def first(path, pattern):
    rx = re.compile(pattern)
    for n, ln in code_lines(path):
        if rx.search(ln):
            return n, ln
    return None, None


for p in (LIB, PRE, P05):
    if not os.path.isfile(p):
        print(f"{os.path.relpath(p, ROOT)} is missing")
        sys.exit(0)

# ── 1. the measure, driven ──────────────────────────────────────────
if first(LIB, rf"^\s*{FN}\s*\(\)") == (None, None):
    findings.append(f"lib/host.sh does not define {FN}")
else:
    with tempfile.TemporaryDirectory() as td:
        os.makedirs(os.path.join(td, "6.1.0-fixture"))
        for rel, want in (("6.1.0-fixture", 0), ("6.1.0-gone", 1)):
            r = subprocess.run(["bash", "-c", f"source '{LIB}'; {FN}"], capture_output=True, text=True,
                               env={**os.environ, "AEGIS_KERNEL_RELEASE": rel, "AEGIS_MODULES_DIR": td},
                               timeout=30)
            what = "present" if want == 0 else "gone"
            if r.returncode != want:
                findings.append(f"{FN} with the running kernel's module tree {what} answered rc "
                                f"{r.returncode}, not {want}: it does not decide by the tree")
            if r.stdout.strip():
                findings.append(f"{FN} wrote on stdout with the tree {what} (stdout is sacred)")
            if want == 1 and "reboot" not in r.stderr.lower():
                findings.append(f"{FN} with the tree gone says nothing about a reboot on stderr: "
                                f"the remedy is not told")

# ── 2. the preflight: after pkg_update, and a FAIL ──────────────────
n_upd, _ = first(PRE, r"(^|[;&|(]\s*)pkg_update\b")
n_ask, ln_ask = first(PRE, rf"(^|[;&|(]\s*){FN}\b")
if n_ask is None:
    findings.append(f"the preflight never asks {FN}")
else:
    if n_upd is None or n_ask < n_upd:
        findings.append(f"the preflight asks {FN} (line {n_ask}) before its pkg_update"
                        f"{'' if n_upd is None else f' (line {n_upd})'}: the upgrade that removes the tree runs after the measure")
    if not re.search(rf"{FN}\b.*\|\|\s*bad\b", ln_ask):
        findings.append(f"the preflight's {FN} (line {n_ask}) does not turn a gone tree into a FAIL (bad)")

# ── 3. phase 05: after pkg_update, and a gate ───────────────────────
n_upd5, _ = first(P05, r"(^|[;&|(]\s*)(run_cmd\s+)?(retry_net\s+\d+\s+)?pkg_update\b")
n_gate, ln_gate = first(P05, rf"^\s*gate\s+\"?[\w-]+\"?\s+{FN}\b")
if n_gate is None:
    findings.append(f"phase 05 has no gate on {FN}")
elif n_upd5 is None or n_gate < n_upd5:
    findings.append(f"phase 05 gates {FN} (line {n_gate}) before its pkg_update"
                    f"{'' if n_upd5 is None else f' (line {n_upd5})'}")

for f in findings:
    print(f)
print(f"SCOPE: {FN} driven 2 ways against a fixture module tree; aegis-preflight and 05-host.sh read "
      f"without comments, calls in command position")
