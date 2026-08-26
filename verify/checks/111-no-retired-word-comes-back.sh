# title: no word retired from the glossary comes back to the code
# origin: new in v3 — the ES->EN rename of 2026-08-24
check() {
# The ratchet of the conversion to English. Moving 34,600 lines of
# language is not dangerous because of what gets translated badly: it is
# dangerous because for weeks the two forms live side by side, and one
# new file written out of the old habit is enough for the retired name
# to stay alive —and then «one concept, one name» stops being true
# without anything saying so. It is rule 3 of the CLI's design, born of
# the TEN same-concept-two-name collisions the v2 register documents:
# edge/borde, backup/respaldo, rotate/rotar, canary/canario,
# template/plantilla, tenant/organización.
#
# The list is NOT written here: it is DERIVED from docs/glossary.md §3,
# which is the document a human reads. A list in the check and another
# in the doc is exactly the pair that drifts apart — and the day they
# drift, the one nobody reads wins.
#
# WHOLE words (-w: letters, digits and underscore are word characters).
# Until 2026-08-26 this was a substring match, and it could not express
# the rename it exists for: retiring `usa` would have flagged `usage`
# in share/exit-codes.txt and in cAdvisor's metric names, retiring
# `organizacion` would have flagged `aegis-organizaciones`, and so on
# for 49 living compounds. A hyphen IS a boundary on purpose: the
# hyphenated compounds (`sin-nombre`, `obs-ntfy-publico-responde`) are
# Spanish themselves and pending, while every false positive found was
# a suffix extension. The price: a plural or a derived form escapes,
# and needs its own row.
#
# Only the lines that are NOT comments are looked at. A comment, and a
# document, MAY name a retired word when they are telling the story:
# several do, and that narration is the most valuable thing this code
# has. What it cannot do is stay in the code.
GLOS="$AEGIS_ROOT/docs/glossary.md"
[[ -f "$GLOS" ]] || { skip "docs/glossary.md does not exist: there is no list to derive from"; return; }

RETIRED="$(sed -n '/^## 3\. /,/^## 3b\. /p' "$GLOS" \
             | sed -n 's/^| `\([^`]*\)` | .*/\1/p')"
[[ -n "$RETIRED" ]] || { skip "the glossary's §3 table is empty"; return; }

D111="" ; N111=0
while IFS= read -r word; do
    [[ -z "$word" ]] && continue
    N111=$((N111+1))
    # nc: without whole-line comments, which is the idiom the rest of
    # the verifier already speaks (verify/lib.sh).
    # verify/teeth/ stays OUT, and not for convenience: a tooth contains
    # deliberately broken code —that is literally its job— and several
    # of them have to write the retired word in order to reintroduce the
    # regression they watch. Putting them in scope would make the
    # ratchet bite the teeth that test it. Its own tooth discovered
    # this, on the first run.
    HITS="$(command grep -rIn --exclude-dir=.git --exclude-dir=teeth --exclude='*.md' -Fw -- "$word" \
                "$AEGIS_ROOT/bin" "$LIBS" "$LIBEXEC" "$AEGIS_ROOT/init" \
                "$AEGIS_ROOT/verify" "$AEGIS_ROOT/share" "$SEED" 2>/dev/null \
            | grep -vE ':[0-9]+:[[:space:]]*(#|//)' || true)"
    [[ -n "$HITS" ]] && D111="$D111 '$word' came back to the code: $(echo "$HITS" | head -3 | cut -d: -f1,2 | tr '\n' ' ');"
done <<< "$RETIRED"

printf '    %s retired words watched\n' "$N111"
if [[ -n "$D111" ]]; then fail "the glossary says these words were retired and they are still there:$D111"
else pass "none of the $N111 retired words appears in code (comments may tell the story)"; fi
}
