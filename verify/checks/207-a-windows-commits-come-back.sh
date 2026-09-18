# title: a window's commits revert one by one and leave the tree byte for byte the same
# origin: new in v3 — 2026-09-18, an update window is allowed to change things only because it can undo them (plan/17)
check() {
# THE PROMISE, EXERCISED RATHER THAN DECLARED.
#
# A window updates the platform without a human awake because
# everything it does can be undone without one either. That promise is
# worth what it has been tested at, and testing it on the live instance
# means breaking the live instance on purpose. So it is tested here, on
# a real copy of the seed's platform in a throwaway directory, calling
# the very functions the window calls: no mock and no second
# implementation, because a way back that only exists in a test double
# is a way back nobody has walked.
#
# What is demanded: the edits land where the inventory said; a commit
# carries only what the window wrote; reverting newest first returns
# the tree byte for byte; a commit that does NOT revert cleanly stops
# the walk instead of leaving a state nobody described; and an edit
# whose line no longer reads as expected is refused rather than written
# blind.
D207=""
[[ -f "$AEGIS_ROOT/lib/aegis/window.py" ]] || { skip "there is no window machinery yet: nothing to undo"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/207.py" ]] || { fail "check 207 has no sidecar: the way back was never walked"; return; }
command -v git >/dev/null || { skip "git is not here, and a window's way back IS git"; return; }

OUT207="$(python3 "$AEGIS_ROOT/verify/checks/207.py" "$AEGIS_ROOT" 2>&1)"
RC207=$?
if (( RC207 != 0 )); then
    fail "the exercise of check 207 itself failed (rc $RC207) and the way back was not walked: $OUT207"
    return
fi
SCOPE207=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE207="${hit#SCOPE: }" ;;
        *)       D207="$D207 $hit;" ;;
    esac
done <<< "$OUT207"

printf '    %s\n' "${SCOPE207:-the scope was not reported}"
if [[ -n "$D207" ]]; then
    fail "the way back does not come all the way back:$D207"
else
    pass "every commit a window makes reverts, in the right order, to the same tree, and what does not revert says so ($SCOPE207)"
fi
}
