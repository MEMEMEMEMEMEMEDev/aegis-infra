"""Check 232 — cleaning the cloud cleans the ENCRYPTED state too, and the
plaintext copies `tofu state rm` leaves behind reach neither disk nor git.

2026-09-23, the first cloud instance: phase 25 detected a tunnel left by a
failed apply, deleted it in Cloudflare and purged the plaintext tfstate —
but the state lives encrypted since #46, and the wrapper decrypted the
deleted tunnel right back before the apply, which died on
PUT .../cfd_tunnel/<id>/configurations → 404. Three runs in a row.

Read out of the phase, and driven: the seed's .gitignore is asked with
`git check-ignore` about the four shapes a tofu state can take.
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = sys.argv[1]
PH = os.path.join(ROOT, "init", "phases", "25-edge-tofu.sh")
GI = os.path.join(ROOT, "seed", "platform", ".gitignore")
findings = []
driven = 0

src = "\n".join(l for l in open(PH, encoding="utf-8").read().splitlines()
                if not re.match(r"^\s*#", l))

# the dirty-cloud block: from the deletion of leftovers to the apply
i0 = src.find("leftovers from a previous run in Cloudflare")
i1 = src.find("apply -auto-approve", i0)
block = src[i0:i1] if 0 <= i0 < i1 else ""
if not block:
    findings.append("phase 25 no longer has the dirty-cloud block before the apply")
else:
    if not re.search(r'"\$TOFU"\s+-chdir="\$TUNNEL_ENV"\s+state rm\s+"\$_r"', block):
        findings.append("after deleting the tunnel in Cloudflare, phase 25 does not drop it from the "
                        "state THROUGH the wrapper: the encrypted copy brings it back and the apply "
                        "hits a tunnel that no longer exists")
    if not re.search(r"state list[^\n]*\|\s*awk\s+'/\^module\\\\\.tunnel\\\\\./'", block) \
            and "module\\.tunnel\\." not in block:
        findings.append("phase 25 drops something other than the tunnel module from the state: "
                        "the Access resources still exist in the cloud and must stay")
    if not re.search(r"find\s+\"\$TUNNEL_ENV\"[^\n]*terraform\.tfstate\.\*\.backup[^\n]*shred", block):
        findings.append("the plaintext copies `tofu state rm` writes next to the state are left on "
                        "disk with the tunnel secret in them")

# ── driven: what git would ignore in a platform repo born from the seed ──
try:
    gi = open(GI, encoding="utf-8").read()
except OSError:
    gi = ""
for line in gi.splitlines():
    if line.strip().startswith("*") and "#" in line:
        findings.append(f".gitignore has a comment on a pattern line ({line.strip()!r}): in a "
                        ".gitignore a mid-line # is part of the pattern, not a comment")
with tempfile.TemporaryDirectory() as td:
    subprocess.run(["git", "init", "-q", td], check=True)
    with open(os.path.join(td, ".gitignore"), "w") as f:
        f.write(gi)
    env = os.path.join(td, "tofu", "envs", "x")
    os.makedirs(env)
    for name, want in (("terraform.tfstate", True), ("terraform.tfstate.backup", True),
                       ("terraform.tfstate.1790127263.backup", True),
                       ("terraform.tfstate.enc.json", False)):
        r = subprocess.run(["git", "-C", td, "check-ignore", "-q", f"tofu/envs/x/{name}"],
                           capture_output=True)
        driven += 1
        ignored = r.returncode == 0
        if ignored != want:
            findings.append(f"the seed's .gitignore {'lets through' if want else 'ignores'} "
                            f"{name}: " + ("a plaintext state with the tunnel secret would be committed"
                                           if want else "the encrypted state must be versioned"))

for f in findings:
    print(f)
print(f"SCOPE: the dirty-cloud block read, and the seed's .gitignore driven {driven} times with git check-ignore")
