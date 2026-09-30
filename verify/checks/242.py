"""Check 242 — the host families the docs publish are the ones the door
accepts, and every name the docs use is DRIVEN through the door.

2026-09-23, the distro line. The rule lives in lib/host.sh
(AEGIS_HOST_SUPPORTED_DEFAULT and the minimum per family). Three
documents say it in words: the Host row of both READMEs and the
requirements table of docs/journeys/your-machine.md. When a family is
opened (a commit of the main line), the three have to move with it; when
they promise more than the door gives, an operator installs on a machine
that is then refused. Check 200 crosses the disk requirement the same
way; this one crosses the host.

Read: each supported family with its minimum, and the list of names the
READMEs say are refused. Driven: an os-release is built from each name
the docs use, and host_supported has to answer what the docs promise.
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
findings = []
driven = 0

LIB = os.path.join(ROOT, "lib", "host.sh")
DOCS = {
    "README.md": os.path.join(ROOT, "README.md"),
    "README.en.md": os.path.join(ROOT, "README.en.md"),
    "docs/journeys/your-machine.md": os.path.join(ROOT, "docs", "journeys", "your-machine.md"),
}
for p in (LIB, *DOCS.values()):
    if not os.path.isfile(p):
        print(f"{os.path.relpath(p, ROOT)} is missing")
        sys.exit(0)

lib = "\n".join(l for l in open(LIB, encoding="utf-8").read().splitlines() if not re.match(r"^\s*#", l))
m = re.search(r'^AEGIS_HOST_SUPPORTED_DEFAULT="([a-z ]+)"', lib, re.M)
if not m:
    print("lib/host.sh declares no AEGIS_HOST_SUPPORTED_DEFAULT")
    sys.exit(0)
supported = m.group(1).split()
mins = {}
for fam, var in (("ubuntu", "AEGIS_HOST_MIN_UBUNTU"), ("debian", "AEGIS_HOST_MIN_DEBIAN")):
    mm = re.search(r'^' + var + r'="([0-9.]+)"', lib, re.M)
    if mm:
        mins[fam] = mm.group(1)
# the words each family goes by in the docs
WORD = {"ubuntu": "Ubuntu", "debian": "Debian", "arch": "Arch"}
# every name the READMEs may list as refused → an os-release of that
# system, the newest shape, so that a refusal is by family and not by
# version
OSR = {
    "Ubuntu": 'ID=ubuntu\nVERSION_ID="{v}"\nPRETTY_NAME="Ubuntu {v}"\n',
    "Debian": 'ID=debian\nVERSION_ID="{v}"\nPRETTY_NAME="Debian GNU/Linux {v}"\n',
    "Arch": 'ID=arch\nPRETTY_NAME="Arch Linux"\nBUILD_ID=rolling\n',
    "CachyOS": 'ID=cachyos\nID_LIKE=arch\nPRETTY_NAME="CachyOS"\n',
    "Fedora": 'ID=fedora\nVERSION_ID=42\nPRETTY_NAME="Fedora Linux 42"\n',
    "Mint": 'ID=linuxmint\nID_LIKE="ubuntu debian"\nVERSION_ID="22"\nPRETTY_NAME="Linux Mint 22"\n',
    "Pop!_OS": 'ID=pop\nID_LIKE="ubuntu debian"\nVERSION_ID="24.04"\nPRETTY_NAME="Pop!_OS 24.04 LTS"\n',
}
FAMILY_OF = {"Ubuntu": "ubuntu", "Debian": "debian", "Arch": "arch", "CachyOS": "arch",
             "Fedora": "rhel", "Mint": "unknown", "Pop!_OS": "unknown"}
NEWEST = {"ubuntu": "26.04", "debian": "13"}


def host_row(path):
    for line in open(path, encoding="utf-8"):
        if re.match(r"^\|\s*\*\*Host\*\*\s*\|", line):
            return line.strip()
    return None


def journey_row(path):
    for line in open(path, encoding="utf-8"):
        if re.match(r"^\|\s*Ubuntu|^\|\s*(Ubuntu|Debian|Arch)\b.*or newer", line):
            return line.strip()
    return None


def promised(text):
    """(family, minimum) for every «Ubuntu 24.04 or newer / o superior»,
    and the families named bare with «rolling»."""
    out = {}
    for w, v in re.findall(r"\b(Ubuntu|Debian)\s+\(?([0-9][0-9.]*)\)?\s*(?:or newer|o superior)", text):
        out[FAMILY_OF[w]] = v
    if re.search(r"\bArch(?: Linux)?\b[^|(]*\(rolling\)", text) or re.search(r"\bArch Linux\s*\(rolling\)", text):
        out["arch"] = ""
    return out


def refused_names(text):
    mm = re.search(r"(?:Otras distribuciones|Other distributions)\s*\(([^)]*)\)", text)
    if not mm:
        return None
    return [n.strip() for n in mm.group(1).split(",") if n.strip()]


def drive(body, want, label):
    global driven
    with tempfile.TemporaryDirectory() as td:
        f = os.path.join(td, "os-release")
        with open(f, "w") as fh:
            fh.write(body)
        r = subprocess.run(["bash", "-c", f"source '{LIB}'; host_supported"], capture_output=True,
                           text=True, env={**os.environ, "AEGIS_OS_RELEASE": f})
    driven += 1
    if r.returncode != want:
        findings.append(f"{label}: host_supported answered rc {r.returncode}, the docs promise "
                        + ("acceptance" if want == 0 else "a refusal"))


for name, path in DOCS.items():
    row = host_row(path) if name.startswith("README") else journey_row(path)
    if not row:
        findings.append(f"{name} has no Host row to read")
        continue
    # what the row promises, family by family
    prom = promised(row.split("Otras distribuciones")[0].split("Other distributions")[0]
                    .split("any other system")[0].split("cualquier otro sistema")[0])
    for fam in supported:
        if fam not in prom:
            findings.append(f"{name} does not publish {WORD[fam]} as a host aegis installs on, and the "
                            f"door accepts it: the docs lag behind the door")
        elif fam in mins and prom[fam] != mins[fam]:
            findings.append(f"{name} publishes {WORD[fam]} {prom[fam]} and the door asks for "
                            f"{mins[fam]}: two minimums, one of them wrong")
    for fam in prom:
        if fam not in supported:
            findings.append(f"{name} publishes {WORD.get(fam, fam)} as a host aegis installs on, and the "
                            f"door refuses it: an operator would install on a machine that is then "
                            f"turned away")
    # driven: what it promises is let in, at the minimum it names
    for fam, v in prom.items():
        if fam in supported:
            drive(OSR[WORD[fam]].format(v=v or ""), 0, f"{name} promises {WORD[fam]} {v}".strip())
    # the refused list (READMEs only): nothing supported in it, and each
    # name really refused
    if name.startswith("README"):
        ref = refused_names(row)
        if ref is None:
            findings.append(f"{name}'s Host row no longer lists the distributions that are refused")
            continue
        for n in ref:
            if n not in OSR:
                findings.append(f"{name} says «{n}» is refused and this check has no os-release for "
                                f"it: teach it here, or it is a name nobody drove")
                continue
            fam = FAMILY_OF[n]
            if fam in supported:
                findings.append(f"{name} still lists {n} as refused, and the door accepts its family "
                                f"({fam})")
                continue
            drive(OSR[n].format(v=NEWEST.get(fam, "")), 1, f"{name} says {n} is refused")

for f in findings:
    print(f)
print(f"SCOPE: door = {' '.join(supported)} (" + ", ".join(f"{k}>={v}" for k, v in mins.items() if k in supported)
      + f"); 3 documents read; {driven} names driven through host_supported")
