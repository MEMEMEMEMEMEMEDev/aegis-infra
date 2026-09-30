"""Check 240 — every package the host gets goes through lib/pkg.sh, by a
name the table knows, and the table says the RIGHT thing per family.

2026-09-23: apt-get was called by name, with Ubuntu's package names, in
the preflight and phases 00 and 05. Debian shares both; Arch shares
neither. lib/pkg.sh is the one place that knows the manager and the
names. Three readings, one of them driven:

  1. nobody outside lib/pkg.sh calls a package manager (two exceptions,
     each with its reason, below);
  2. every canonical name the product installs is in the table, and the
     table has no row nobody installs (an orphan row is a name nobody
     measured against a use);
  3. pkg_install is RUN, with sudo trapped, on a Debian and an Arch
     os-release: the command it would have issued is compared with the
     measured names.
"""
import os
import re
import stat
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
findings = []
PKG = os.path.join(ROOT, "lib", "pkg.sh")
HOST = os.path.join(ROOT, "lib", "host.sh")
P05 = os.path.join(ROOT, "init", "phases", "05-host.sh")
PINS = os.path.join(ROOT, "seed", "platform", "ansible", "inventory", "group_vars", "all.yml")

# where a manager may still be named, and why
EXCEPT = {
    # the tofu .deb: a local-path apt install, debian-only by nature (the
    # Arch branch downloads the tarball; plan/01, the Arch item)
    "init/phases/05-host.sh": re.compile(r"apt_locked\(\)\s*\{|apt_locked install -y /tmp/tofu\.deb"),
    # the update window's apt layers (plan/01 §2.3 and §2.6)
    "libexec/aegis-update": re.compile(r"."),
}
MANAGER = re.compile(r"\b(apt-get|apt install|pacman|dnf|zypper|dpkg -i)\b")


def nc(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return [(i, l) for i, l in enumerate(f.read().splitlines(), 1) if not re.match(r"^\s*#", l)]


for p in (PKG, HOST, P05, PINS):
    if not os.path.isfile(p):
        print(f"{os.path.relpath(p, ROOT)} is missing")
        sys.exit(0)

# ── 1. the manager is named in one place ─────────────────────────────
for top in ("bin", "libexec", "init", "lib"):
    for dp, dns, fns in os.walk(os.path.join(ROOT, top)):
        dns[:] = [d for d in dns if d not in ("__pycache__", ".venv")]
        for fn in fns:
            path = os.path.join(dp, fn)
            rel = os.path.relpath(path, ROOT)
            if rel == "lib/pkg.sh" or fn.endswith(".py"):
                continue
            try:
                lines = nc(path)
            except (OSError, UnicodeDecodeError):
                continue
            for i, l in lines:
                m = MANAGER.search(l)
                if not m:
                    continue
                # a message that names the manager is not a call to it
                if re.match(r'^\s*(echo|log_\w+|warn|bad|ok|info|die)\b', l.strip()):
                    continue
                ex = EXCEPT.get(rel)
                if ex and ex.search(l):
                    continue
                findings.append(f"{rel}:{i} calls «{m.group(1)}» by name: install through "
                                f"lib/pkg.sh (pkg_install/pkg_update) with a canonical name")

# ── 2. the names: used ⇔ in the table ────────────────────────────────
pkg_src = "\n".join(l for _, l in nc(PKG))
rows = set()
for m in re.finditer(r"^\s+([a-z0-9|.-]+)\)\s+deb=", pkg_src, re.M):
    rows.update(m.group(1).split("|"))
for m in re.finditer(r"^\s+([a-z0-9|.-]+)\)\s*$\n\s+deb=", pkg_src, re.M):
    rows.update(m.group(1).split("|"))

used = {}
for rel in ("libexec/aegis-preflight", "init/phases/00-preflight.sh", "init/phases/05-host.sh",
            "init/phases/20-k3s.sh"):
    for i, l in nc(os.path.join(ROOT, rel)):
        for m in re.finditer(r"\bpkg_(?:install|names)\s+((?:[a-z0-9.-]+[ \t]*)+)", l):
            for w in m.group(1).split():
                used.setdefault(w, f"{rel}:{i}")

# the playbook's base packages come from the table, for BOTH families
PLAY = os.path.join(ROOT, "seed", "platform", "ansible", "playbooks", "bootstrap-host.yml")
play = "\n".join(l for _, l in nc(PLAY))
k20 = "\n".join(l for _, l in nc(os.path.join(ROOT, "init", "phases", "20-k3s.sh")))
if '-e "$AEGIS_BASE_PKGS_JSON"' not in k20:
    findings.append("phase 20 does not hand the table's base packages to bootstrap-host.yml")
if not re.search(r"community\.general\.pacman:\s*\n\s+name:\s*\"\{\{ aegis_base_packages \}\}\"", play):
    findings.append("bootstrap-host.yml's arch branch does not install the names the table gave it")
if not re.search(r"ansible\.builtin\.apt:\s*\n\s+name:\s*\"\{\{ aegis_base_packages \| default", play):
    findings.append("bootstrap-host.yml's debian branch does not install the names the table gave it")
if re.search(r"^\s+name:\s*\[curl", play, re.M):
    findings.append("bootstrap-host.yml still lists its own base package names")
# the loop's catch-all installs every tool pinned "apt" by its own name
pins = {}
for l in open(PINS, encoding="utf-8"):
    m = re.match(r'^\s+([a-z0-9-]+):\s*"([^"]+)"', l)
    if m:
        pins[m.group(1)] = m.group(2)
loop = next((l for _, l in nc(P05) if re.match(r"^for t in ", l)), "")
for t in re.findall(r"[a-z0-9-]+", loop.split(" in ", 1)[-1].split(";")[0]):
    if pins.get(t) == "apt":
        used.setdefault(t, "05-host.sh's loop (pinned apt)")
if not loop:
    findings.append("phase 05 has no «for t in …» loop to read the distro-installed tools from")

for name, where in sorted(used.items()):
    if name not in rows:
        findings.append(f"«{name}» is installed ({where}) and lib/pkg.sh's table has no row for it")
for name in sorted(rows - set(used)):
    findings.append(f"lib/pkg.sh's table has a row for «{name}» and nothing installs it (an orphan)")

# ── 3. driven: the command each family would issue ───────────────────
WANT = {
    "debian13": ('ID=debian\nVERSION_ID="13"\n',
                 "apt-get -o DPkg::Lock::Timeout=600 install -y -qq apache2-utils python3-yaml python3-venv rsync gh"),
    "ubuntu2404": ('ID=ubuntu\nVERSION_ID="24.04"\n',
                   "apt-get -o DPkg::Lock::Timeout=600 install -y -qq apache2-utils python3-yaml python3-venv rsync gh"),
    "cachyos": ('ID=cachyos\nID_LIKE=arch\n',
                "pacman -S --needed --noconfirm --quiet apache python-yaml rsync github-cli"),
}
driven = 0
with tempfile.TemporaryDirectory() as td:
    bindir = os.path.join(td, "bin"); os.makedirs(bindir)
    log = os.path.join(td, "sudo.log")
    trap = os.path.join(bindir, "sudo")
    with open(trap, "w") as fh:
        fh.write(f"#!/bin/sh\n[ \"$1\" = DEBIAN_FRONTEND=noninteractive ] && shift\necho \"$*\" >> '{log}'\n")
    os.chmod(trap, stat.S_IRWXU)
    for name, (body, want) in WANT.items():
        osr = os.path.join(td, name)
        with open(osr, "w") as fh:
            fh.write(body)
        if os.path.exists(log):
            os.remove(log)
        r = subprocess.run(["bash", "-c", f"source '{HOST}'; source '{PKG}'; "
                            "pkg_install htpasswd python3-yaml python3-venv rsync gh"],
                           capture_output=True, text=True, timeout=30,
                           env={**os.environ, "AEGIS_OS_RELEASE": osr,
                                "PATH": bindir + ":" + os.environ.get("PATH", "")})
        driven += 1
        got = open(log).read().strip() if os.path.exists(log) else ""
        if r.returncode != 0 or got != want:
            findings.append(f"pkg_install on {name} issued «{got or 'nothing'}» (rc {r.returncode}); "
                            f"the measured names say «{want}»")
    # the names phase 20 hands to Ansible, on arch
    r = subprocess.run(["bash", "-c", f"source '{HOST}'; source '{PKG}'; "
                        "pkg_names curl ca-certificates iptables jq conntrack | paste -sd' ' -"],
                       capture_output=True, text=True, timeout=30,
                       env={**os.environ, "AEGIS_OS_RELEASE": os.path.join(td, "cachyos")})
    driven += 1
    if r.stdout.strip() != "curl ca-certificates iptables jq conntrack-tools":
        findings.append(f"pkg_names on arch gave «{r.stdout.strip()}» for the playbook's base packages")
    # a name outside the table stops the install, it does not skip it
    if os.path.exists(log):
        os.remove(log)
    r = subprocess.run(["bash", "-c", f"source '{HOST}'; source '{PKG}'; pkg_install jq nosuchpkg"],
                       capture_output=True, text=True, timeout=30,
                       env={**os.environ, "AEGIS_OS_RELEASE": os.path.join(td, "debian13"),
                            "PATH": bindir + ":" + os.environ.get("PATH", "")})
    driven += 1
    if r.returncode == 0 or os.path.exists(log):
        findings.append("pkg_install with a name outside the table installed the rest and went on: "
                        "an unknown name must stop the install")

for f in findings:
    print(f)
print(f"SCOPE: bin/ libexec/ init/ lib/ read for package managers; {len(used)} names installed vs "
      f"{len(rows)} rows; pkg_install driven {driven} times (debian, ubuntu, an arch derivative, "
      f"an unknown name) with sudo trapped")
