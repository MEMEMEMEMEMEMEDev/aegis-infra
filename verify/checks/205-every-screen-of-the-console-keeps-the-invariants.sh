# title: every screen of the console keeps the invariants, not only the first one
# origin: new in v3 — 2026-09-16, the console grew nine screens drawn from the same readings (plan/16 §6)
check() {
# Checks 122 and 127 hold the two invariants on the overview, which is
# the screen the corpus was built for. The console has nine screens and
# a page per project now — deployments, domains, storage, plans, the
# machine, the round — each one a different SUBSET of the same readings
# organised for a person, and a rule measured on one screen is a rule
# the other eight can break in silence: a verdict computed over a
# filtered list, a row drawn hatched because a reading was absent, an
# age left inside a fold.
#
# So every case is rendered through every screen, and the project page
# where the case carries one, and each result is read back for the same
# attributes: no state invented, every source with its time and its age
# on the page, every source about a command that was consulted, and a
# verdict never kinder than the readings.
D205=""
[[ -f "$LIBS/aegis/screens.py" ]] || { skip "there are no screens yet ($LIBS/aegis/screens.py): nothing beyond the overview to hold"; return; }
[[ -d "$AEGIS_ROOT/console/cases" ]] || { skip "there is no corpus to render: this check has no subject"; return; }

OUT205="$(python3 "$AEGIS_ROOT/verify/checks/205.py" "$AEGIS_ROOT" 2>&1)"
RC205=$?
if (( RC205 != 0 )); then
    fail "the renderer of check 205 itself failed (rc $RC205) and no screen was read back: $OUT205"
    return
fi
SCOPE205=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE205="${hit#SCOPE: }" ;;
        *)       D205="$D205 $hit;" ;;
    esac
done <<< "$OUT205"

printf '    %s\n' "${SCOPE205:-the scope was not reported}"
if [[ -n "$D205" ]]; then
    fail "a screen of the console breaks what the first one keeps:$D205"
else
    pass "every screen of every case invents no state, dates and ages every source it draws, and never says fine over a reading that was not ($SCOPE205)"
fi
}
