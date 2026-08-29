# title: no machine's address and no machine's name is written into the product
# origin: new in v3 — 2026-08-26, before giving the artifact a remote
check() {
# The address of a CONCRETE machine is identity of an INSTANCE, and the
# product does not carry instances. It is the same rule that keeps the
# operator's domain out of seed/ (check 086) and the same reason: an
# artifact that names one machine is an artifact that was written for
# that machine, and it stops being something anyone can install.
#
# It arrived the day the artifact was about to get a git remote: a
# document at the root carried the lab VPS's public IP four times,
# together with its break-glass procedure. In a private repository the
# exposure is small, but «small» is not the standard — the standard is
# that the product does not know which machine it runs on.
#
# WHAT IS ALLOWED, and why each one:
#
#   · private ranges (10/8, 172.16/12, 192.168/16) and loopback — they
#     name nobody: they are the same everywhere;
#   · 0.0.0.0 and 255.255.255.255 — they are not addresses, they are
#     «all» and «broadcast»;
#   · the documentation ranges of RFC 5737 (192.0.2.0/24,
#     198.51.100.0/24, 203.0.113.0/24), which name nobody by definition
#     and are what an EXAMPLE should use. Python already classifies them
#     as non-global, so they cost no allowlist entry — a property found
#     by writing a tooth with one and watching it not bite;
#   · the allowlist below, which is PUBLIC INFRASTRUCTURE with an owner
#     and a reason. It is short on purpose: every line is a public
#     service the init consults, never a machine of the operator's.
#   · a line carrying `# not-an-address: <why>`. Four numbers with dots
#     between them are a version as often as an address, and no regex
#     tells them apart. The declaration is visible and greppable, which
#     is the same bargain every other declared exception in this tree
#     makes — and the line below is the demonstration, because this
#     check bit its own documentation on the first run:
#     not-an-address: `cloud-init 26.1.0.4` is a version, and it parses
#     as a perfectly good public address.
#
# verify/teeth/ is OUT of scope, and for the same reason check 111
# excludes it: a tooth CONTAINS the regression on purpose — that is
# literally its job — and the tooth of this very check has to write an
# address in order to prove the check bites. Sweeping the teeth would
# make the ratchet bite the thing that tests it.
#
# Anything else is a machine, and a machine does not belong here.
#
# The record (plan/, ENCARGO.md, EJECUTADO.md) is swept TOO. It was
# tempting to leave it out — it is prose, and prose tells the story —
# but an address does not stop being an address because it appears in a
# narrative, and the record travels in the same repository.
D116=""

if python3 - "$AEGIS_ROOT" <<'EOF'
import ipaddress, pathlib, re, sys

ROOT = pathlib.Path(sys.argv[1])

# Public infrastructure the product legitimately names. Each entry says
# WHO uses it and WHY, because an allowlist without reasons is a place
# to hide things.
ALLOWED = {
    "1.1.1.1": "Cloudflare's public resolver — phase 00 and lib/checks.sh ask IT, and not "
               "the system's resolver, whether the domain is delegated: asking the resolver "
               "that may itself be broken is how that check would lie",
}

# An allowlist entry with no reason is a hiding place. The reason is not
# decoration: it is what a future reader needs in order to decide whether
# the entry still belongs, and an empty one turns this table into the
# comfortable place to put the next machine.
_unexplained = [ip for ip, why in ALLOWED.items() if not (why or "").strip()]
if _unexplained:
    print(f"    the allowlist carries {len(_unexplained)} address(es) with NO reason "
          f"({', '.join(_unexplained)}): an exception without a reason is a hiding place")
    sys.exit(1)

IPV4 = re.compile(r'(?<![\d.])((?:\d{1,3}\.){3}\d{1,3})(?![\d.])')

# `.git` and `__pycache__` are noise wherever they turn up; verify/teeth
# is excluded by its PATH and not by its bare name. The difference is not
# pedantry, and it was pointed out over the sibling check 151: matching
# the NAME against every component would exempt any future directory
# called `teeth` at any depth, and what would quietly stop being swept
# here is ADDRESSES.
SKIP_ANYWHERE = {".git", "__pycache__"}
TEETH = ("verify", "teeth")

def is_swept(rel):
    return not (SKIP_ANYWHERE & set(rel.parts)) and rel.parts[:2] != TEETH

found, n_files = {}, 0

for f in sorted(ROOT.rglob("*")):
    if not f.is_file() or not is_swept(f.relative_to(ROOT)):
        continue
    try:
        text = f.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue          # binary: an address in a binary is another problem
    n_files += 1
    lines = text.splitlines()
    for m in IPV4.finditer(text):
        raw = m.group(1)
        line_no = text[:m.start()].count("\n")
        if line_no < len(lines) and "not-an-address:" in lines[line_no]:
            continue      # declared, with its reason, on the line itself
        try:
            ip = ipaddress.ip_address(raw)
        except ValueError:
            continue      # 999.1.2.3 and friends: a version number, not an address
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_multicast \
           or ip.is_unspecified or ip.is_reserved:
            continue
        if raw in ALLOWED:
            continue
        found.setdefault(raw, []).append(f"{f.relative_to(ROOT)}:{line_no + 1}")

print(f"    {n_files} files swept · {len(ALLOWED)} public addresses with a declared owner")
for ip, where in sorted(found.items()):
    print(f"    the address {ip} is written into the product ({', '.join(where[:3])}"
          f"{' and %d more' % (len(where) - 3) if len(where) > 3 else ''}): "
          "that is a concrete machine, and the product does not know which machine it "
          "runs on. If it is public infrastructure the init consults, add it to this "
          "check's allowlist WITH ITS REASON; if it is a machine, it belongs in the "
          "operator's ~/.ssh/config and in the provider's panel, not here")
sys.exit(1 if found else 0)
EOF
then :; else D116="$D116 an address (see the detail above);"; fi

# ── the NAME of a machine is an address too ─────────────────────────
# Extended 2026-08-29. Everything above asks about NUMBERS, and the
# sweep that found the four IPs was blind to the line that named the
# node: the seed installed k3s with the name the node has on the machine
# where the seed was first written. It shipped for months. `kubectl get
# nodes` on ANY installation would have printed one operator's node
# name, and the class is precisely the one the header of this check
# states — «an artifact that names one machine is an artifact that was
# written for that machine». A hostname is how a machine is addressed
# where there are no numbers; leaving it out of scope was an accident of
# the regex, not a decision.
#
# HOW IT ASKS, and it is the opposite of the sweep above: there, anything
# that is not a declared exception is a machine; here, anything that is
# not a declared GENERIC name is a machine. The direction is inverted on
# purpose because the population is tiny — the seed writes ONE node name
# — and because a name has no structure a regex could classify: 10.0.0.1
# announces that it is private, `aegis-node` and one person's node name
# are the same seven-to-twenty characters of letters and hyphens. So the
# generic ones are enumerated, WITH the reason each is generic, and a
# name arriving without a row is presumed to be somebody's machine.
#
# What makes a name generic is not that it looks impersonal: it is that
# it comes out THE SAME on every installation. That is the very property
# that lets 10.0.0.0/8 through above — «they name nobody: they are the
# same everywhere».
#
# Placeholders are not names: a value carrying `$`, `{`, `<` or the
# seed's `__NAME__` spelling is a hole for the instance to fill, and
# filling it is the instance's business, not the product's.
if python3 - "$AEGIS_ROOT" <<'EOF'
import pathlib, re, sys

ROOT = pathlib.Path(sys.argv[1])

# The node names the product is allowed to write, with WHY each one is
# generic. Same lock as the address table above: a row with no reason is
# a hiding place, and it is checked, not trusted.
GENERIC_NODES = {
    "aegis-node": "the single k3s node the seed installs — the same string on every "
                  "installation, so it names nobody; seed/platform/ansible/inventory/"
                  "group_vars/all.yml is the only place that writes it",
}

_unexplained = [n for n, why in GENERIC_NODES.items() if not (why or "").strip()]
if _unexplained:
    print(f"    the generic-node table carries {len(_unexplained)} name(s) with NO reason "
          f"({', '.join(_unexplained)}): an exception without a reason is a hiding place")
    sys.exit(1)

# The three spellings a node name arrives in: the k3s flag, the ansible
# variable, and the Kubernetes field.
#
# The capture demands that the value START with a letter, a digit, or
# the first character of a hole (`$`, `_`, `{`, `<`). That is not
# cosmetics: with a looser capture this check READS ITSELF — the regex
# source below contains the literal `nodeName:` followed by a bracket,
# and the first version of this block accused its own line 170 of
# naming a machine called `[`. Found by running it, which is the only
# way this class ever gets found.
NAMED = re.compile(r'(?:--node-name[= \t]|node[-_]name:[ \t]*|nodeName:[ \t]*)["\']?([A-Za-z0-9$_{<][^"\'\s#]*)')
# by PATH, for the reason written over the address sweep above
SKIP_ANYWHERE = {".git", "__pycache__"}
TEETH = ("verify", "teeth")

def is_swept(rel):
    return not (SKIP_ANYWHERE & set(rel.parts)) and rel.parts[:2] != TEETH

def is_hole(v):
    return bool(set("${}<>") & set(v)) or (v.startswith("__") and v.endswith("__"))

found, n_named = [], 0
for f in sorted(ROOT.rglob("*")):
    if not f.is_file() or not is_swept(f.relative_to(ROOT)):
        continue
    try:
        text = f.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    for i, line in enumerate(text.splitlines(), 1):
        for m in NAMED.finditer(line):
            v = m.group(1)
            if is_hole(v):
                continue
            n_named += 1
            if v not in GENERIC_NODES:
                found.append(f"{f.relative_to(ROOT)}:{i} → {v}")

print(f"    {n_named} node name(s) written · {len(GENERIC_NODES)} declared generic")
for where in found:
    print(f"    {where}: that is the name of ONE machine, and every installation would "
          "print it in `kubectl get nodes`. If the name is the same on every install, add "
          "it to this check's generic table WITH ITS REASON; if it is a machine of the "
          "operator's, it belongs in their inventory, not in the seed")
sys.exit(1 if found else 0)
EOF
then :; else D116="$D116 a node name (see the detail above);"; fi

if [[ -n "$D116" ]]; then fail "an instance's identity is baked into the product:$D116"
else pass "no machine's address and no machine's name is written into the product (private ranges are nobody's, every public address has a declared owner, and every node name is the same on every installation)"; fi
}
