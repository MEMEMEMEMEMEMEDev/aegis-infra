# title: the product carries no literal credential
# origin: new in v3 — 2026-08-29, an automated alert over a negative tooth
check() {
# Third sibling of 116 (no machine's address) and 117 (no person's
# name). Those two keep an INSTANCE's identity out of the artifact; this
# one keeps out anything with the SHAPE of a credential, whether or not
# it ever opened anything.
#
# It was born the morning a scanner flagged a "Bearer Token" in the
# public repository. The forensics — two scanners over the whole
# history, and a sha256 comparison against the encrypted store — came
# back FALSE POSITIVE: the only credential-shaped strings in the tree
# were three deliberately WRONG passwords that aegis-rotate's negative
# teeth used to prove a service rejects a bad login. Nothing had leaked.
#
# The lesson is not "the scanner was wrong". It is that proving a
# negative cost a morning, that the reader of a public repo cannot run
# that forensics themselves, and that the workaround — an inline marker
# telling the scanner to look away — is itself dangerous: the marker was
# appended after a `\` line continuation, bash read it as an escaped
# space instead, and the three calls it was protecting had been dead
# since the moment it was added. A tree with zero literals needs neither
# the forensics nor the marker, so that is the property measured here.
#
# STATIC AND SELF-SUFFICIENT. It does NOT shell out to gitleaks: the
# person running `aegis verify` on a fresh host does not have it, and a
# check that silently degrades to "not installed → green" is the exact
# disease this verifier exists to kill. `.gitleaks.toml` at the root is
# the OTHER half — it tunes the scanner that runs before opening a repo
# (docs/protocols/opening-a-repo.md) — and neither replaces the other.
#
# WHAT COUNTS AS A LITERAL, and what is deliberately allowed:
#
#   · `Authorization: Basic` followed by 16+ characters of real base64.
#     Sixteen is already 12 bytes of `user:pass`; shorter than that is
#     an example nobody could use.
#   · `Bearer` followed by a token of 16+ characters that is a VALUE.
#   · `"password": "…"` inline in a JSON, with 12+ characters of value.
#
#   Allowed, because it is not a value:
#   · anything carrying `$`, `{`, `<`, `%`, a backtick or a backslash —
#     a shell/python/JS interpolation, a printf format, or a
#     documentation placeholder such as `Bearer <key>`. This is why
#     prose needs no exemption of its own: a document that writes the
#     placeholder passes, and a document that pastes a REAL token does
#     not, which is the behaviour wanted.
#
#     Only the OPENING characters are on that list, and that is a
#     correction made the same day: `}` and `>` were on it too, and
#     they turned the promise above into a lie. A real token pasted
#     inside a JSON body — `{"Authorization": "Bearer <32 real
#     characters>"}` — came out GREEN, because the capture runs to the
#     `"}` that closes the object and that `}` was then read as an
#     interpolation. The same for a Basic inside a JSON, and for a
#     token inside an HTML attribute, which `>` closed. That is the
#     most natural way for a token to arrive — inside the body it
#     belongs to — and it is the shape of the alert that started all
#     this. The closing punctuation of the surrounding syntax is
#     TRIMMED by value() now instead of being read as a hole, and an
#     interpolation still passes, because `${VAR}` and `<key>` are
#     unmistakable by their opening character alone.
#   · a value spelled `__NAME__` — the seed's placeholder convention,
#     whose owner is check 003. It needs a rule of its own and it was
#     the first thing the tooth found: underscore is not one of the
#     characters above and it is not in base64's alphabet either, so
#     `__CF_TUNNEL_TOKEN__` (19 characters) was being read as a Bearer
#     value. A placeholder accused of being a secret is how a check
#     teaches its operator to ignore it.
#   · a value under the length floors above.
#
# verify/teeth/ is OUT of scope, for the third time and for the same
# reason spelled out in 111, 116 and 117: a tooth CONTAINS the
# regression on purpose. This check's own red tooth therefore writes
# into a file that IS swept — otherwise it would prove nothing.
D151=""

if python3 - "$AEGIS_ROOT" <<'EOF'
import pathlib, re, sys

ROOT = pathlib.Path(sys.argv[1])

# `.git` and `__pycache__` are noise wherever they appear; verify/teeth
# is excluded by its PATH and not by its bare name. The difference is not
# pedantry: `p in SKIP_DIRS for p in f.parts` would exempt any future
# directory called `teeth` at any depth, and here the thing that would
# stop being swept is CREDENTIALS.
SKIP_ANYWHERE = {".git", "__pycache__"}
TEETH = ("verify", "teeth")

def is_swept(rel):
    return not (SKIP_ANYWHERE & set(rel.parts)) and rel.parts[:2] != TEETH

# A value that carries any of these is an interpolation, a format string
# or a documentation placeholder — not something anybody can log in with.
# OPENING characters only: see the header for what putting `}` and `>` in
# here cost.
NOT_A_VALUE = set("${<%`\\")

def is_placeholder(v):
    return bool(NOT_A_VALUE & set(v)) or (v.startswith("__") and v.endswith("__"))

BASIC  = re.compile(r'Basic[ \t]+(\S+)')
BEARER = re.compile(r'Bearer[ \t]+(\S+)')
PWJSON = re.compile(r'"password"[ \t]*:[ \t]*"([^"]*)"')
# real base64, padding included; the alphabet is closed on purpose so a
# hyphenated word ("Basic auth-header") cannot be mistaken for one
B64 = re.compile(r'^[A-Za-z0-9+/]{16,}={0,2}$')

def value(raw):
    """the token with the punctuation of the surrounding syntax removed
    (the quote that closes a shell -H, a trailing comma in a dict, the
    `"}` that closes the JSON object the header was pasted into, the `>`
    that closes an HTML attribute)"""
    return raw.strip("'\",;)}>]")

found, n_files = [], 0
for f in sorted(ROOT.rglob("*")):
    if not f.is_file():
        continue
    where = f.relative_to(ROOT)
    if not is_swept(where):
        continue
    try:
        text = f.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    n_files += 1
    for i, line in enumerate(text.splitlines(), 1):
        for m in BASIC.finditer(line):
            v = value(m.group(1))
            if is_placeholder(v):
                continue
            if B64.match(v):
                found.append((f"{where}:{i}", "an Authorization Basic with real base64"))
        for m in BEARER.finditer(line):
            v = value(m.group(1))
            if is_placeholder(v) or len(v) < 16:
                continue
            found.append((f"{where}:{i}", "a Bearer token written out as a value"))
        for m in PWJSON.finditer(line):
            v = m.group(1)
            if is_placeholder(v) or len(v) < 12:
                continue
            found.append((f"{where}:{i}", "a password field with a literal value in an inline JSON"))

print(f"    {n_files} files swept for the three shapes (Basic, Bearer, inline JSON password)")
for where, what in found:
    print(f"    {where} carries {what}: whether or not it opens anything, a public tree "
          "that carries something credential-SHAPED costs an automated alert and a morning "
          "of proving a negative. If it is a credential, rotate it and purge the history; "
          "if it is a NEGATIVE tooth, manufacture the value at run time "
          "(libexec/aegis-rotate's _wrong_password is the pattern); if it is documentation, "
          "write the placeholder (<key>) instead of a value")
sys.exit(1 if found else 0)
EOF
then :; else D151="$D151 (see the detail above);"; fi

if [[ -n "$D151" ]]; then fail "the product carries a literal credential:$D151"
else pass "no literal credential in the product: no Basic with base64, no Bearer written as a value, no password inline in a JSON — the placeholders are placeholders"; fi
}
