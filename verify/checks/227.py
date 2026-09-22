"""Check 227 — the host is asked about FIRST, and a machine aegis cannot
install on is refused before anything on it is touched.

2026-09-22: a CachyOS machine (pacman, no apt) got a sudoers drop-in,
IPv6 switched off, a half k3s and a wizard answered for nothing. The
only «is this Ubuntu?» lived in the playbook of phase 20; phase 00 only
warned about the version, and the preflight's apt-get failed in silence.

Read out of the source, and driven: `host_supported` is fed the
os-release of nine real systems, and the preflight and the orchestrator
are run on a fake CachyOS with `sudo` trapped, so that «refused before
acting» is measured and not read.
"""
import os
import re
import stat
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
findings = []
driven = 0


def lines_nc(path):
    with open(path, encoding="utf-8") as f:
        return [ln for ln in f.read().splitlines() if not re.match(r"^\s*#", ln)]


LIB = os.path.join(ROOT, "lib", "host.sh")
PRE = os.path.join(ROOT, "libexec", "aegis-preflight")
INIT = os.path.join(ROOT, "libexec", "aegis-init")
P00 = os.path.join(ROOT, "init", "phases", "00-preflight.sh")
PLAY = os.path.join(ROOT, "seed", "platform", "ansible", "playbooks", "bootstrap-host.yml")

for p in (LIB, PRE, INIT, P00, PLAY):
    if not os.path.isfile(p):
        print(f"{os.path.relpath(p, ROOT)} is missing: the host rule has nowhere to live or to be asked")
        sys.exit(0)


def first(lines, pred):
    for i, ln in enumerate(lines):
        if pred(ln):
            return i
    return None


# ── the rule is the playbook's rule, one number in one place ─────────
lib = "\n".join(lines_nc(LIB))
m = re.search(r'^AEGIS_HOST_MIN_UBUNTU="([0-9.]+)"', lib, re.M)
play = "\n".join(lines_nc(PLAY))
pm = re.search(r"distribution_version'\]\s+is\s+version\('([0-9.]+)',\s*'>='\)", play)
if not m:
    findings.append("lib/host.sh declares no AEGIS_HOST_MIN_UBUNTU: the minimum lives nowhere")
elif not pm:
    findings.append("bootstrap-host.yml no longer asserts a minimum Ubuntu version: the host rule "
                    "has no second opinion to agree with")
elif m.group(1) != pm.group(1):
    findings.append(f"lib/host.sh asks for Ubuntu {m.group(1)} and the playbook asserts "
                    f"{pm.group(1)}: the door and the wall disagree, and the gap between them is "
                    f"a half-installed machine")
if "distribution'] == 'Ubuntu'" not in play:
    findings.append("bootstrap-host.yml no longer asserts the distribution is Ubuntu")

# ── the question comes before the first action, in the three places ──
pre = lines_nc(PRE)
i_q = first(pre, lambda l: "host_supported" in l)
i_s = first(pre, lambda l: re.search(r"(^|[\s;&|(])sudo\s", l) is not None)
if i_q is None:
    findings.append("aegis preflight never asks host_supported: it acts on any machine")
elif i_s is not None and i_s < i_q:
    findings.append(f"aegis preflight runs sudo (line «{pre[i_s].strip()[:60]}») BEFORE it asks "
                    f"whether this machine is one aegis can install on")
elif not any("exit 1" in l for l in pre[i_q:i_q + 6]):
    findings.append("aegis preflight asks host_supported but does not stop on a refusal")

ini = lines_nc(INIT)
i_q = first(ini, lambda l: "host_supported" in l)
i_reset = first(ini, lambda l: "clear_state" in l)
i_loop = first(ini, lambda l: l.strip() == "started=false")
if i_q is None:
    findings.append("aegis init never asks host_supported: --from 20 walks around phase 00 "
                    "straight into k3s")
else:
    if i_reset is not None and i_reset < i_q:
        findings.append("aegis init resets its state before it asks about the host")
    if i_loop is not None and i_loop < i_q:
        findings.append("aegis init starts the phase loop before it asks about the host")
    if "die" not in ini[i_q] and not any("die" in l for l in ini[i_q:i_q + 3]):
        findings.append("aegis init asks host_supported and does not stop on a refusal")

p00 = lines_nc(P00)
i_q = first(p00, lambda l: "host_supported" in l)
i_cfg = first(p00, lambda l: l.strip().startswith("ensure_config"))
i_apt = first(p00, lambda l: re.search(r"\bsudo\b|apt-get", l) is not None)
if i_q is None:
    findings.append("phase 00 never asks host_supported")
else:
    if i_cfg is not None and i_cfg < i_q:
        findings.append("phase 00 runs the wizard before it asks about the host: every answer is "
                        "wasted on a machine that was never going to work")
    if i_apt is not None and i_apt < i_q:
        findings.append("phase 00 reaches sudo/apt-get before it asks about the host")
    if "die" not in p00[i_q]:
        findings.append("phase 00 asks host_supported and warns instead of stopping")

# ── driven: the function against nine real os-release files ─────────
CASES = {
    "cachyos": ('NAME="CachyOS Linux"\nPRETTY_NAME="CachyOS"\nID=cachyos\nID_LIKE=arch\n', 1),
    "arch": ('PRETTY_NAME="Arch Linux"\nID=arch\nBUILD_ID=rolling\n', 1),
    "mint": ('PRETTY_NAME="Linux Mint 22"\nID=linuxmint\nID_LIKE="ubuntu debian"\nVERSION_ID="22"\n', 1),
    "debian": ('PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"\nID=debian\nVERSION_ID="12"\n', 1),
    "ubuntu2204": ('PRETTY_NAME="Ubuntu 22.04.4 LTS"\nID=ubuntu\nVERSION_ID="22.04"\n', 1),
    # the two that discriminate the NAME rule: a version at or above the
    # minimum under another name. Without them «any Linux» passed this
    # check, because every other refusal came from the version (tooth
    # red_5, 2026-09-22).
    "fedora42": ('PRETTY_NAME="Fedora Linux 42 (Workstation Edition)"\nID=fedora\nVERSION_ID=42\n', 1),
    "pop2404": ('PRETTY_NAME="Pop!_OS 24.04 LTS"\nID=pop\nID_LIKE="ubuntu debian"\nVERSION_ID="24.04"\n', 1),
    "ubuntu2404": ('PRETTY_NAME="Ubuntu 24.04.3 LTS"\nID=ubuntu\nID_LIKE=debian\nVERSION_ID="24.04"\n', 0),
    "ubuntu2604": ('PRETTY_NAME="Ubuntu 26.04.1 LTS"\nID=ubuntu\nVERSION_ID="26.04"\n', 0),
}
with tempfile.TemporaryDirectory() as td:
    for name, (body, want) in CASES.items():
        f = os.path.join(td, name)
        with open(f, "w") as fh:
            fh.write(body)
        r = subprocess.run(["bash", "-c", f"source '{LIB}'; host_supported"],
                           capture_output=True, text=True,
                           env={**os.environ, "AEGIS_OS_RELEASE": f})
        driven += 1
        if r.returncode != want:
            findings.append(f"host_supported on {name} answered rc {r.returncode}, expected {want}"
                            + (": a machine aegis cannot install on would be let in" if want else
                               ": a supported Ubuntu would be turned away"))
        elif want and r.stdout.strip():
            findings.append(f"host_supported writes its refusal to stdout on {name}: stdout is sacred")

    # ── driven: preflight and init on a fake CachyOS, sudo trapped ────
    bindir = os.path.join(td, "bin")
    os.makedirs(bindir)
    log = os.path.join(td, "sudo.log")
    trap = os.path.join(bindir, "sudo")
    with open(trap, "w") as fh:
        fh.write(f"#!/bin/sh\necho called >> '{log}'\nexit 1\n")
    os.chmod(trap, stat.S_IRWXU)
    env = {**os.environ, "AEGIS_OS_RELEASE": os.path.join(td, "cachyos"),
           "PATH": bindir + ":" + os.environ.get("PATH", ""), "AEGIS_ROOT": ROOT}
    for label, argv in (("aegis preflight", [os.path.join(ROOT, "bin", "aegis"), "preflight"]),
                        ("aegis init --from 20 --check",
                         [os.path.join(ROOT, "bin", "aegis"), "init", "--from", "20", "--check"])):
        r = subprocess.run(argv, capture_output=True, text=True, env=env,
                           stdin=subprocess.DEVNULL, timeout=60)
        driven += 1
        calls = open(log).read().count("called") if os.path.exists(log) else 0
        if r.returncode != 1:
            findings.append(f"{label} on CachyOS returned rc {r.returncode}, expected 1 (wrong host)")
        if calls:
            findings.append(f"{label} on CachyOS called sudo {calls} time(s) before refusing")
        if "nothing was changed" not in (r.stdout + r.stderr):
            findings.append(f"{label} on CachyOS refused without saying that nothing was changed")
        if os.path.exists(log):
            os.remove(log)

for f in findings:
    print(f)
print(f"SCOPE: the rule agrees with the playbook, the question sits before the first action in "
      f"the preflight, the orchestrator and phase 00; driven {driven} times (nine os-release "
      f"files, and two commands on a CachyOS with sudo trapped)")
