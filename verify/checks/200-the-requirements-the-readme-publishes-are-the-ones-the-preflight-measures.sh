# title: the requirements both READMEs publish are the ones plans.yaml declares and the preflight measures
# origin: new in v3 — measured on 2026-09-09: one requirement, three homes, two values, and nobody could say which was real
check() {
# Free disk on `/` was demanded in THREE places with TWO values:
# `aegis preflight` wanted 25 GiB, the init's own gate wanted 20, and
# both READMEs published 25. One of them was wrong. None of them could
# be checked against the others, because none of them was readable from
# anywhere but itself — and it had been that way long enough that
# nobody could say which number was the requirement.
#
# The number lives in `plans.yaml` under `anfitrion` now, and the two
# readers ask for it. This check closes the third side of the triangle:
# what the product PUBLISHES has to be what it MEASURES.
#
# BOTH DIRECTIONS, which is the idiom check 010 earned the hard way
# when `AI` was added to the wizard and nothing noticed:
#
#   · a threshold the artifact enforces and no README states — the
#     reader plans a machine and finds out at install time;
#   · a threshold a README states and the artifact does not enforce —
#     a promise with nothing behind it, which is the worse of the two
#     because it reads as a measurement.
#
# And the same for the two READMEs against each other. The English one
# is the door for everybody who does not read Spanish, and it has
# drifted before: on 2026-08-29 it was 250 lines against 595.
RD_ES="$AEGIS_ROOT/README.md"
RD_EN="$AEGIS_ROOT/README.en.md"
for f in "$RD_ES" "$RD_EN"; do
    [[ -f "$f" ]] || { fail "the README is not there: $f"; return; }
done

OUT="$(python3 - "$P/plans.yaml" "$LIBEXEC/aegis-preflight" "$PHASES/00-preflight.sh" \
                "$RD_ES" "$RD_EN" <<'PY'
import re, sys, yaml

plans_p, pre_p, phase_p, es_p, en_p = sys.argv[1:6]

try:
    a = (yaml.safe_load(open(plans_p, encoding="utf-8")) or {}).get("anfitrion") or {}
except yaml.YAMLError as e:
    print(f"FAILplans.yaml could not be parsed ({e!r}): the declared requirement is "
          "the thing everything else is compared against")
    raise SystemExit

declared = a.get("disco_minimo")
if not declared:
    print("FAIL`anfitrion.disco_minimo` is not declared in plans.yaml: with no single "
          "home, the readers go back to holding their own opinions")
    raise SystemExit

m = re.match(r"^(\d+)\s*(Gi|G)$", str(declared).strip())
if not m:
    print("FAIL`anfitrion.disco_minimo` is %r, which this check cannot compare against "
          "prose stated in gigabytes" % declared)
    raise SystemExit
gib = int(m.group(1))

def code(path):
    """The file without comments. A comment EXPLAINING that the number
    moved to plans.yaml must not read as the number staying here."""
    return "\n".join(l.split("#", 1)[0]
                     for l in open(path, encoding="utf-8").read().splitlines())

# ── 1 · no reader holds a copy ───────────────────────────────────────
for path, label in ((pre_p, "libexec/aegis-preflight"),
                    (phase_p, "init/phases/00-preflight.sh")):
    body = code(path)
    if "requires" not in body:
        print("FAIL%s does not ask `aegis host requires` for the free-disk threshold: "
              "a reader with its own copy is how one requirement came to have two "
              "values" % label)
    for lit in re.findall(r'-ge\s+["\']?(\d{2,})\b', body):
        print("FAIL%s compares free disk against the literal %s instead of the "
              "declared %dGi: the second opinion is back" % (label, lit, gib))

# ── 2 · both READMEs publish the number the artifact enforces ────────
DISK = re.compile(r'(\d+)\s*(?:GB|GiB|G)\s*(?:libres|free)', re.I)
for path, label in ((es_p, "README.md"), (en_p, "README.en.md")):
    txt = open(path, encoding="utf-8").read()
    stated = {int(x) for x in DISK.findall(txt)}
    if not stated:
        print("FAIL%s states no free-disk requirement: the artifact refuses to install "
              "below %dGi and the reader plans a machine without knowing" % (label, gib))
    elif gib not in stated:
        print("FAIL%s publishes %s of free disk and the artifact enforces %dGi: a "
              "promise that does not match what happens reads as a measurement and is "
              "not one" % (label, "/".join(f"{s}G" for s in sorted(stated)), gib))

# ── 3 · and the host profile is offered where the requirements are ───
# The requirements table is where somebody decides whether their
# machine will do. A product that can MEASURE that and does not say so
# there is keeping the answer to itself.
for path, label in ((es_p, "README.md"), (en_p, "README.en.md")):
    txt = open(path, encoding="utf-8").read()
    if "aegis host" not in txt:
        print("FAIL%s never mentions `aegis host`: it is the command that answers the "
              "question that section exists to raise — will this machine do — and the "
              "reader is left estimating instead" % label)

print("    disco_minimo %dGi declared, enforced by 2 readers, published by 2 READMEs"
      % gib)
PY
)" || { fail "the reading of the requirements could not be completed"; return; }

printf '%s\n' "$OUT" | grep -v '^FAIL'
if printf '%s\n' "$OUT" | grep -q '^FAIL'; then
    fail "published against measured: $(printf '%s\n' "$OUT" | sed -n 's/^FAIL//p' | paste -sd'; ')"
else
    pass "the free-disk requirement has one home, two readers that ask for it, and two READMEs that publish it"
fi
}
