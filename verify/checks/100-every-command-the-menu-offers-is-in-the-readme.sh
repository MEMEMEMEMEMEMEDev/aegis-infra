# title: every command the menu offers is in the README, and every one the README names exists
# origin: new in v3 — measured on 2026-09-12: five commands written, tested, given teeth, and named in no README
check() {
# MEASURED, NOT IMAGINED. On 2026-09-12 `aegis traffic`, `aegis
# capacity`, `aegis builds`, `aegis tenant` and `aegis console` had been
# written, tested, given checks and teeth and run against a live
# instance — and they appeared NOWHERE in either README. Five commands
# that existed only in their own docstrings. Writing this check found
# two more that had been that way longer: `aegis image` and
# `aegis host`.
#
# That is the quietest way for a product to shrink. Nothing fails: the
# command works, `aegis --help` lists it, every check is green. It
# simply is not part of what anybody who did not write it can find, and
# the README is the only place a stranger looks.
#
# BOTH DIRECTIONS, the idiom this repository earned the hard way:
#
#   · a command the menu offers and the README does not name — written
#     and unfindable;
#   · a command the README names and nothing provides — a promise with
#     nothing behind it, which is worse, because it reads as a
#     description of something real.
#
# The menu is not a list kept here: it is derived from the very metadata
# `bin/aegis` reads to print it. A command marked `aegis-hidden` is
# hidden from this check too — the maintainer's tools are not part of
# what the product offers.
D100=""
[[ -f "$AEGIS_ROOT/README.md" ]] || { skip "there is no README.md: this check has no subject"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/100.py" ]] || { fail "check 100 has no sidecar: the menu and the README were never compared"; return; }

OUT100="$(python3 "$AEGIS_ROOT/verify/checks/100.py" "$AEGIS_ROOT" 2>&1)"
RC100=$?
if (( RC100 != 0 )); then
    fail "the exercise of check 100 itself failed (rc $RC100) and nothing was compared: $OUT100"
    return
fi
SCOPE100=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE100="${hit#SCOPE: }" ;;
        *)       D100="$D100 $hit;" ;;
    esac
done <<< "$OUT100"

printf '    %s\n' "${SCOPE100:-the scope was not reported}"
if [[ -n "$D100" ]]; then
    fail "the product offers something the README does not publish, or publishes something it does not offer:$D100"
else
    pass "every command of the menu is named in the README, in its own group's row, and every command the README names exists ($SCOPE100)"
fi
}
