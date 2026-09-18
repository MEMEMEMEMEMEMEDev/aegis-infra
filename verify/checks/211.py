"""Check 211 — the tools of the host, their download branch and their pin.

Two independent readings of one artifact, the way 206 does it: this
file finds the branches of `install_binary` with its own regex and the
pins with its own parse, and then demands the two agree. It shares no
code with the phase, so a phase that stops verifying cannot take the
check with it.

The pairing, and why each half exists:

  a tool WITH a download branch  → that branch must verify what it
      downloaded. A branch that curls a binary into /tmp and installs
      it is the state this check was written to end.

  a tool WITHOUT a download branch → it falls to the apt case, and apt
      installs whatever the distribution's line carries today. Its pin
      in group_vars must therefore say `apt`. A literal version there
      is a number nobody delivers, and `aegis update` reads it as a
      real pin, measures it against upstream and proposes a bump the
      phase cannot install — a window that reports a change that never
      happened.
"""
import os
import re
import sys

ROOT = sys.argv[1]
PHASE = os.path.join(ROOT, "init", "phases", "05-host.sh")
GV = os.path.join(ROOT, "seed", "platform", "ansible", "inventory",
                  "group_vars", "all.yml")
findings = []

if not os.path.isfile(PHASE):
    print("SCOPE: there is no phase 05")
    sys.exit(0)
text = open(PHASE, encoding="utf-8").read()

# ── the branches of install_binary, read as text ─────────────────────
# The body between `install_binary() {` and the closing of its case.
m = re.search(r"^install_binary\(\)\s*\{(.*?)^\}", text, re.M | re.S)
if not m:
    print("install_binary is not in phase 05: nothing splits «where each tool comes from» "
          "from «when it is installed», and this check cannot pair a tool with its download")
    print("SCOPE: the phase does not carry the expected shape")
    sys.exit(0)
body = m.group(1)
# Each branch: `name)` ... `;;`. The catch-all `*)` is the apt one.
branches = {}
for bm in re.finditer(r"^\s{8}([a-z0-9|]+|\*)\)(.*?);;", body, re.M | re.S):
    for name in bm.group(1).split("|"):
        branches[name] = bm.group(2)

if "*" not in branches:
    findings.append("install_binary has no catch-all branch: a tool nobody wrote a case "
                    "for would fall through and be silently NOT installed")

# ── the pins, read straight out of group_vars ────────────────────────
pins_by_tool = {}
if os.path.isfile(GV):
    gv = open(GV, encoding="utf-8").read()
    um = re.search(r"^userland_pins:\s*$", gv, re.M)
    if um:
        for line in gv[um.end():].splitlines():
            if line.strip() and not line.startswith((" ", "\t", "#")):
                break
            pm = re.match(r"^\s+([a-z0-9_]+):\s*[\"']?([^\"'\s#]+)", line)
            if pm:
                pins_by_tool[pm.group(1)] = pm.group(2)
if not pins_by_tool:
    findings.append("no userland pin could be read from group_vars: the pairing between a "
                    "tool and the way it is installed could not be made at all")

# ── the tools the loop actually installs ─────────────────────────────
lm = re.search(r"^for t in ([^;]+); do\s*$", text, re.M)
tools = lm.group(1).split() if lm else []
if not tools:
    findings.append("the loop that installs the userland could not be read: nobody knows "
                    "which tools this phase claims to install")

# ── (a) a branch that downloads has to prove what it downloaded ──────
# «downloads» is curl, wget or a URL; «proves» is fetch_verified, or a
# sha256sum/cosign comparison written out in the branch itself. The
# check does not demand ONE function name — it demands the property,
# so a branch that verifies another way stays green.
DOWNLOADS = re.compile(r"\b(curl|wget)\b|https?://")
PROVES = re.compile(r"\bfetch_verified\b|\bsha256sum\b|\bcosign\s+verify")
for name, branch in sorted(branches.items()):
    if name == "*":
        continue
    if DOWNLOADS.search(branch) and not PROVES.search(branch):
        findings.append(f"the branch for «{name}» downloads and nothing in it proves the "
                        f"bytes: https authenticates the server, not the artifact")

# ── (b) a tool with no branch of its own is apt's, and its pin says so
for tool in tools:
    pin = pins_by_tool.get(tool)
    if pin is None:
        findings.append(f"«{tool}» is installed by the loop and has no pin in "
                        f"userland_pins: the phase would die reading it")
        continue
    has_branch = tool in branches
    if pin == "apt" and has_branch:
        findings.append(f"«{tool}» is pinned `apt` and yet install_binary carries a branch "
                        f"of its own for it: the pin says the distribution decides and the "
                        f"code says otherwise")
    if pin != "apt" and not has_branch:
        findings.append(f"«{tool}» is pinned at «{pin}» and falls to the apt branch, which "
                        f"installs whatever the distribution's line carries. The number is "
                        f"not delivered by anything, and `aegis update` reads it as a real "
                        f"pin and would propose a bump nobody can install")

# ── the verifier itself has to fail loudly, not quietly ──────────────
# A checksum that is computed, compared and then logged is WORSE than no
# checksum at all: it reads as protection to everybody who greps for it,
# and the install goes ahead anyway. So the property demanded is not
# «there is a comparison» but «the branch where the comparison fails
# cannot continue».
fv = re.search(r"^fetch_verified\(\)\s*\{(.*?)^\}", text, re.M | re.S)
if fv:
    body_fv = fv.group(1)
    mismatch = re.search(r"if\s*\[\[[^\]]*!=[^\]]*\]\]\s*;?\s*then(.*?)^\s*fi\b",
                         body_fv, re.S | re.M)
    if not mismatch:
        findings.append("fetch_verified does not compare what it downloaded against what "
                        "was published: it fetches a checksum and does nothing with it")
    elif not re.search(r"\b(die|exit\s+[1-9]|return\s+[1-9])\b", mismatch.group(1)):
        findings.append("fetch_verified compares the checksum and CARRIES ON when it does "
                        "not match: a comparison whose failure is a log line is worse than "
                        "none, because everybody who greps for it reads it as protection")
elif any(PROVES.search(b) and "fetch_verified" in b for b in branches.values()):
    findings.append("the branches call fetch_verified and phase 05 does not define it")

for f in findings:
    print(f)
print(f"SCOPE: {len(tools)} tool(s) in the loop, {len([b for b in branches if b != '*'])} "
      f"with a download branch, {len(pins_by_tool)} pin(s) read from group_vars")
