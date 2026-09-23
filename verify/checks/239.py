"""Check 239 — no tool that lives only in sbin is called bare, outside sudo.

2026-09-23, lab-debian13: Debian puts /usr/sbin on root's PATH and on
sudo's secure_path, and NOT on a user's (ssh, login shell and tmux all
measured: /usr/local/bin:/usr/bin:/bin:/usr/games). Ubuntu puts it on
everybody's, so a bare `sysctl` worked on every machine aegis had run on
and was «command not found» on the first Debian. Under `sudo` the tool is
found; through /proc or an absolute path it does not need finding.

The list below is MEASURED on Debian 13 (tools the product uses that
`command -v` finds in sbin and not in /usr/local/bin:/usr/bin:/bin), not
recalled. Lexical, like every class check: a tool word in command
position (after a separator or an opening quote) with no sudo in front of
it in its own command.
"""
import os
import re
import sys

ROOT = sys.argv[1]
SBIN_ONLY = ("sysctl modprobe modinfo iptables ip6tables visudo update-ca-certificates nft "
             "swapon swapoff blkid losetup useradd groupadd usermod ufw sshd dmidecode ethtool "
             "tc fstrim sfdisk mkfs.ext4 chronyd ldconfig dmsetup setcap getcap").split()
TOOL = "|".join(re.escape(t) for t in SBIN_ONLY)
# command position: start, a separator, a subshell/substitution opener, or
# an opening quote (gate_diag and wait_for take commands as strings)
CMD = re.compile(r"(?:^|;|&&|\|\||\||\(|\$\(|`|'|\")\s*(?:[A-Z_]+=\S*\s+)*(" + TOOL + r")(?=\s|$|\)|;|'|\")")
PYCALL = re.compile(r"""\[\s*["'](""" + TOOL + r""")["']""")
CASE_ARM = re.compile(r"^\s*[\w.*\-\"'|]+\)")
SUDO_SHELL = re.compile(r"\bsudo\b[^;|&]*\b(?:bash|sh)\s+-c\b")

findings, scanned = [], 0


def logical_lines(text):
    buf, start = "", 0
    for i, ln in enumerate(text.splitlines(), 1):
        if not buf:
            start = i
        if re.match(r"^\s*#", ln) and not buf:
            continue
        if ln.endswith("\\"):
            buf += ln[:-1] + " "
            continue
        yield start, buf + ln
        buf = ""
    if buf:
        yield start, buf


def scan_shell(path):
    global scanned
    scanned += 1
    rel = os.path.relpath(path, ROOT)
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    for n, line in logical_lines(text):
        # a case arm's PATTERN (`age|jq|iptables)`) names words, it runs
        # nothing: drop it and read what the arm does
        line = CASE_ARM.sub(" ", line)
        for m in CMD.finditer(line):
            before = line[:m.start(1)]
            if SUDO_SHELL.search(before):
                continue          # inside a `sudo bash -c "…"`: root's PATH
            # its own command: from the last separator to the tool. A sudo
            # there (`… | sudo -S -p '' visudo`) is the fix, not a finding
            seg = re.split(r";|&&|\|\||\||\$\(|`", before)[-1]
            if re.search(r"\bsudo\b", seg):
                continue
            findings.append(f"{rel}:{n} calls «{m.group(1)}» bare: on Debian it is not on a "
                            f"user's PATH (sudo it, give its path, or read /proc)")


def scan_python(path):
    global scanned
    scanned += 1
    rel = os.path.relpath(path, ROOT)
    with open(path, encoding="utf-8", errors="replace") as f:
        for n, line in enumerate(f, 1):
            if re.match(r"^\s*#", line):
                continue
            m = PYCALL.search(line)
            if m and "sudo" not in line[:m.start()]:
                findings.append(f"{rel}:{n} runs «{m.group(1)}» bare from python: on Debian it is "
                                f"not on a user's PATH")


for top in ("bin", "libexec", "init", "lib", "console"):
    base = os.path.join(ROOT, top)
    for dp, dns, fns in os.walk(base):
        dns[:] = [d for d in dns if d not in ("__pycache__", "node_modules", ".venv")]
        for fn in fns:
            p = os.path.join(dp, fn)
            if fn.endswith(".py"):
                scan_python(p)
                continue
            try:
                with open(p, encoding="utf-8", errors="replace") as fh:
                    head = fh.readline()
            except OSError:
                continue
            if fn.endswith(".sh") or "bash" in head or head.startswith("#!/bin/sh"):
                scan_shell(p)

for f in findings:
    print(f)
print(f"SCOPE: {scanned} files of bin/ libexec/ init/ lib/ console/ against {len(SBIN_ONLY)} tools "
      f"measured sbin-only on Debian 13")
