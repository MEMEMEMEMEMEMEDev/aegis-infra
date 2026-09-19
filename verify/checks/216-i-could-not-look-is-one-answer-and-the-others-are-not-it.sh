# title: «I could not look» is one answer of six, and the other five are not it
# origin: new in v3 — 2026-09-18, three different things were wearing that name and the console went permanently grey (plan/17)
check() {
# A VERDICT THAT NEVER CHANGES IS A VERDICT NOBODY READS.
#
# Until 2026-09-18 `aegis update` had four answers and the fourth was
# carrying three different things: an image this instance builds
# itself (there is nobody to ask), a tag scheme nobody can order
# (asked, answered, unorderable), and a registry that timed out (the
# instrument never reached the subject). The first two never change;
# the third usually clears on the next run.
#
# Flattened together they made `inventory` exit 2 every single day on
# a perfectly healthy instance, and the console say «something could
# not be looked at» on every page of it. That is the same disease this
# command was written to treat, one level up and wearing the uniform of
# the cure.
#
# So the six answers are kept apart, and the keeping-apart is checked
# where it can actually break: what the module can return, which group
# each belongs to, which single one becomes `not-evaluable`, whether
# the console has a word for each, and whether the cache is versioned —
# because a renamed state read back out of yesterday's cache is a word
# that means what it used to mean.
D216=""
[[ -f "$AEGIS_ROOT/lib/aegis/upstream.py" ]] || { skip "this artifact does not ask upstream anything"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/216.py" ]] || { fail "check 216 has no sidecar: the answers were never compared"; return; }

OUT216="$(python3 "$AEGIS_ROOT/verify/checks/216.py" "$AEGIS_ROOT" 2>&1)"
RC216=$?
if (( RC216 != 0 )); then
    fail "the exercise of check 216 itself failed (rc $RC216): $OUT216"
    return
fi
SCOPE216=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE216="${hit#SCOPE: }" ;;
        *)       D216="$D216 $hit;" ;;
    esac
done <<< "$OUT216"

printf '    %s\n' "${SCOPE216:-the scope was not reported}"
if [[ -n "$D216" ]]; then
    fail "the answers upstream gives are being flattened:$D216"
else
    pass "every answer is declared, belongs to exactly one group, has a word on the screen, and only the one that means the instrument failed becomes «could not evaluate» ($SCOPE216)"
fi
}
