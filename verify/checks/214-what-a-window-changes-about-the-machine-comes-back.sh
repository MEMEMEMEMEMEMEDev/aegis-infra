# title: everything a window changes about the machine is put back, on every way out
# origin: new in v3 — 2026-09-18, the alert that would have told you is the one that was silenced (plan/17)
check() {
# THE THREE THINGS NOBODY WOULD NOTICE.
#
# A window quiets Jenkins, silences the alerts about the public sites
# and stops the backup clock. All three are right while it runs and all
# three are silent damage afterwards: an instance that builds nothing,
# is deaf about its sites and takes no backups — and not one of them
# announces itself, because the alert that would have told you about
# the sites is precisely the one that was silenced.
#
# So the way back is not «at the end». It is a stack, pushed BEFORE
# each change is made, and run in the exit path of every ending there
# is, including the exception nobody predicted. That last part is the
# only thing here read out of the source rather than driven: whether it
# sits in a `finally` is a fact about control flow.
#
# And the one thing that must NOT come back on its own: the maintenance
# page after a red. Putting a broken instance in front of the public is
# the moment the page exists for.
D214=""
[[ -f "$AEGIS_ROOT/lib/aegis/window.py" ]] || { skip "there is no window machinery yet"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/214.py" ]] || { fail "check 214 has no sidecar: no restore was ever run"; return; }

OUT214="$(python3 "$AEGIS_ROOT/verify/checks/214.py" "$AEGIS_ROOT" 2>&1)"
RC214=$?
if (( RC214 != 0 )); then
    fail "the exercise of check 214 itself failed (rc $RC214): $OUT214"
    return
fi
SCOPE214=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE214="${hit#SCOPE: }" ;;
        *)       D214="$D214 $hit;" ;;
    esac
done <<< "$OUT214"

printf '    %s\n' "${SCOPE214:-the scope was not reported}"
if [[ -n "$D214" ]]; then
    fail "a window can leave the machine as it found it only by luck:$D214"
else
    pass "everything the window changes about the machine is undone in reverse, on every way out, one failure does not stop the rest, the heartbeat is never silenced, and the page does not come down after a red ($SCOPE214)"
fi
}
