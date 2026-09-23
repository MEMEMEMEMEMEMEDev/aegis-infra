"""Check 241 — every host family aegis has code for has its branch
wherever the host differs by family.

2026-09-23, the distro line. The door (lib/host.sh) says which families
have code: AEGIS_HOST_FAMILIES_KNOWN. A family in that list that is
missing ONE branch passes the door and dies halfway, which is the exact
shape of the CachyOS install this line was born from. So the list is
read, and each place where the host differs is asked about each family:

  - the system CA anchor and its refresh (registry-host-trust.yml),
    LOADED as YAML: the anchor map has a key per family;
  - the base packages (bootstrap-host.yml): a task per family;
  - tofu (phase 05): the .deb is debian-only, so a non-debian family
    needs the verified tarball branch;
  - the clock (preflight 4/9): chrony's unit name per family.
"""
import os
import re
import sys

import yaml

ROOT = sys.argv[1]
findings = []
OS_FAMILY = {"ubuntu": "Debian", "debian": "Debian", "arch": "Archlinux"}


def nc(path):
    with open(path, encoding="utf-8") as f:
        return "\n".join(l for l in f.read().splitlines() if not re.match(r"^\s*#", l))


host = nc(os.path.join(ROOT, "lib", "host.sh"))
m = re.search(r'^AEGIS_HOST_FAMILIES_KNOWN="([a-z ]+)"', host, re.M)
known = m.group(1).split() if m else []
if not known:
    print("lib/host.sh declares no AEGIS_HOST_FAMILIES_KNOWN")
    sys.exit(0)
for fam in known:
    if fam not in OS_FAMILY:
        findings.append(f"«{fam}» has code per lib/host.sh and this check does not know its Ansible "
                        f"os_family: teach it here, with the branches below")
osfams = sorted({OS_FAMILY[f] for f in known if f in OS_FAMILY})

# ── the CA anchor, loaded ────────────────────────────────────────────
rht = os.path.join(ROOT, "seed", "platform", "ansible", "playbooks", "registry-host-trust.yml")
tasks = []
for play in yaml.safe_load(open(rht, encoding="utf-8")) or []:
    tasks += play.get("tasks", []) or []
anchor = next((t for t in tasks if t.get("register") == "ca_system"), None)
refresh = next((t for t in tasks if "update-ca" in str(t.get("ansible.builtin.command", ""))), None)
if not anchor:
    findings.append("registry-host-trust.yml has no task that installs the CA into the system store")
else:
    amap = (anchor.get("vars") or {}).get("aegis_ca_anchor") or {}
    for of in osfams:
        if of not in amap:
            findings.append(f"the system CA has no anchor path for os_family {of}: that family's host "
                            f"never trusts the edge's certificate")
    if amap.get("Debian") and not amap["Debian"].startswith("/usr/local/share/ca-certificates/"):
        findings.append("the Debian anchor is not under /usr/local/share/ca-certificates/ (the only "
                        "place update-ca-certificates reads)")
    if amap.get("Archlinux") and not amap["Archlinux"].startswith("/etc/ca-certificates/trust-source/anchors/"):
        findings.append("the Arch anchor is not under /etc/ca-certificates/trust-source/anchors/")
    for of, path in amap.items():
        if not path.endswith(".crt"):
            findings.append(f"the {of} anchor does not end in .crt (update-ca-certificates skips it silently)")
cmd = str((refresh or {}).get("ansible.builtin.command", ""))
if "Archlinux" in osfams and "update-ca-trust" not in cmd:
    findings.append("the trust store refresh never runs update-ca-trust: on arch the anchor is written "
                    "and the bundle never learns it")
if "Debian" in osfams and "update-ca-certificates" not in cmd:
    findings.append("the trust store refresh never runs update-ca-certificates on the debian family")

# ── base packages: a task per family ─────────────────────────────────
play = nc(os.path.join(ROOT, "seed", "platform", "ansible", "playbooks", "bootstrap-host.yml"))
for of in osfams:
    if not re.search(r"- name: Base packages[^\n]*\n(?:\s+[^\n]*\n){1,6}?\s+when: ansible_facts\['os_family'\] == '"
                     + of + "'", play):
        findings.append(f"bootstrap-host.yml has no base-packages task for os_family {of}")

# ── tofu: the .deb is debian-only ────────────────────────────────────
p05 = nc(os.path.join(ROOT, "init", "phases", "05-host.sh"))
tofu = re.search(r"^\s+tofu\)\n(.*?)^\s+;;|^\s+tofu\)\n(.*?);;", p05, re.S | re.M)
body = (tofu.group(1) or tofu.group(2) or "") if tofu else ""
if any(OS_FAMILY[f] != "Debian" for f in known if f in OS_FAMILY):
    # the URL it DOWNLOADS is the tarball (the artifact name alone, the
    # fourth argument, would still say tar.gz over a .deb download)
    if not re.search(r'fetch_verified\s*\\\s*\n\s*"\S*tofu_\$\{pin\}_linux_amd64\.tar\.gz"', body) \
            or body.count("fetch_verified") < 2:
        findings.append("a non-debian family has code, and phase 05 installs tofu only as a .deb "
                        "(no verified tarball branch)")
    if '"$(pkg_family)" == debian' not in body:
        findings.append("phase 05 does not choose tofu's .deb by the package family")

# ── the clock ─────────────────────────────────────────────────────────
pre = nc(os.path.join(ROOT, "libexec", "aegis-preflight"))
if "arch" in known and not re.search(r"systemctl restart chronyd\b", pre):
    findings.append("the preflight's clock repair restarts only chrony.service; on arch the unit "
                    "is chronyd.service")

for f in findings:
    print(f)
print(f"SCOPE: {len(known)} families with code ({' '.join(known)}), os_family {', '.join(osfams)}; "
      f"CA anchor+refresh (loaded), base packages, tofu, the clock")
