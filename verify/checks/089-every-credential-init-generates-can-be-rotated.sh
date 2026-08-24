# title: every credential init GENERATES is known to be rotatable (#82)
# origin: verify-static.sh (v2) ══ 89
check() {
# Rotation was prose until 2026-08-12: rotation-checklist.md had eleven
# items and aegis-rotate.sh mechanized ONE (invalidating the store). A
# person executed the rest from memory, including the step that
# distinguishes "I rotated" from "I rotated and it works".
#
# Mechanizing it brings a new and silent risk: adding a credential to
# init and NOT adding it to the recipe table. That credential would
# exist, would be persisted in the store, and the day it had to be
# rotated nobody would know how — without a single error, because
# nothing names it.
#
# It is the same principle as aegis dev seed's EXCLUSIONES/DELIBERADAS
# tables: a missing entry is an ERROR, not a detail.
#
# It is deliberately NOT measured against init/.state-secrets/. That
# directory is the STATE of a live instance and may not exist in a clean
# checkout; a check tied to it would go green by absence (C15: a check
# tied to a PLACE lies as soon as something moves). It is measured
# against the ARTIFACT: what the phases declare they generate.
D89=""
python3 - "$AEGIS_ROOT/init" "$LIBS" "$LIBEXEC" <<'PY' || D89="$D89 (see the detail above);"
import pathlib, re, sys

init = pathlib.Path(sys.argv[1])
libexec = pathlib.Path(sys.argv[3])
# The rotator stopped being a loose script of init's: it is a command
# (libexec/aegis-rotate, `aegis rotate`). The recipe this check looks
# for is the same; what changed is where it lives.
rotator = libexec / "aegis-rotate"
if not rotator.is_file():
    print(f"    {rotator} does not exist: nobody knows how to rotate ANYTHING"); sys.exit(1)

# 1. what init declares it generates and persists, by reading the
#    phases. Four ways of NAMING material in the store, and all four are
#    needed: the Cloudflare tokens are persisted with the name in a
#    VARIABLE (mint_cf_token does `persist_secret "$store"`), so they
#    only appear as literals on the restore_secret side. Detected
#    because this very check reported them as orphan recipes.
PATTERNS = [
    re.compile(r'\bgen_or_restore(?:_keypair)?\s+([a-z][a-z0-9_]*)'),
    re.compile(r'\bpersist_secret\s+([a-z][a-z0-9_]*)'),
    re.compile(r'\brestore_secret\s+([a-z][a-z0-9_]*)'),
    re.compile(r'STATE_SECRETS/([a-z][a-z0-9_]*)\.enc'),
]
# And the blind spot that remains: a persist_secret whose name comes
# from a variable AND that is never restored by literal would be
# invisible to this check. It cannot be resolved by reading text, so
# instead of faking full coverage, the check NAMES what it cannot see.
INDIRECT = re.compile(r'\bpersist_secret\s+"\$')

generated, indirections = {}, []
for phase in sorted((init / "phases").glob("*.sh")):
    for i, line in enumerate(phase.read_text().splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue          # comments NAME helpers, they do not call them
        code = line.split("#", 1)[0]
        for pat in PATTERNS:
            for n in pat.findall(code):
                generated.setdefault(n, f"{phase.name}:{i}")
        if INDIRECT.search(code):
            indirections.append(f"{phase.name}:{i}")

if not generated:
    print("    NO generated credential was found: the check evaluated nothing")
    sys.exit(1)

# 2. what the recipe table covers. The TABLE is read, not the whole
#    file: a loose name in a comment is not a recipe.
text = rotator.read_text()
tables = re.findall(r"<<'TABLA'\n(.*?)\nTABLA", text, re.S)
if not tables:
    print("    aegis-rotate has no recognizable RECETAS table")
    sys.exit(1)
recipes = {}
for t in tables:
    for line in t.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split("|")
        if len(fields) < 7:
            print(f"    malformed recipe (7 fields expected): {line}")
            sys.exit(1)
        recipes[fields[0]] = fields[1]

CLASSES = {"normal", "delegada", "irreducible", "prohibida", "tofu", "manual"}
bad = []

for n, where in sorted(generated.items()):
    if n not in recipes:
        bad.append(f"'{n}' is generated at {where} and has NO recipe in aegis-rotate: "
                   f"it exists, it is persisted, and nobody knows how to rotate it")
    elif recipes[n] not in CLASSES:
        bad.append(f"'{n}' has an unknown class '{recipes[n]}' (valid: {sorted(CLASSES)})")

# 3. and the other way round: a recipe for something nobody generates
#    any more is an old note, and an old note stops protecting without
#    saying so. Declared exception: tunnel_token is produced by tofu
#    (phase 25), not by the store.
# Material that lives in the store but that init does NOT produce today.
# Every entry is a declared DEBT, not a comfortable exception: the right
# thing is for a phase to generate it. If this list grows without an
# associated task, init and the instance are drifting apart.
NOT_GENERATED_BY_INIT = {
    "tunnel_token":            "produced by tofu in phase 25",
    "argocd_admin_pass":       "debt #86: phase 30 should produce it",
    "argocd_server_secretkey": "debt #86: phase 30 should produce it",
    "cf_access_token":         "debt #88: phase 15 does not know how to mint it yet",
    "access_st_id":            "created by tofu along with the Access apps (#76)",
    "access_st_secret":        "created by tofu along with the Access apps (#76)",
}
for n, cls in sorted(recipes.items()):
    if n not in generated and n not in NOT_GENERATED_BY_INIT:
        bad.append(f"the recipe for '{n}' does not correspond to any credential init "
                   f"generates today: either it stopped being generated, or the note went stale")

for m in bad:
    print(f"    {m}")
if not bad:
    print(f"    {len(generated)} generated credentials, all with a recipe "
          f"({sorted(generated)})", file=sys.stderr)
    if indirections:
        # Green WITH its blind spot in plain view: these lines persist
        # with the name in a variable. Today the restore_secret literal
        # covers them; if tomorrow somebody adds one that is not
        # restored by literal, this check will NOT see it.
        print(f"    (declared blind spot: persist_secret with the name in a variable at "
              f"{', '.join(indirections)} — covered today by their literal restore_secret)",
              file=sys.stderr)
sys.exit(1 if bad else 0)
PY
if [[ -n "$D89" ]]; then fail "rotation recipes:$D89"
else pass "every credential init generates has a declared rotation recipe, and none is left over"; fi
}
