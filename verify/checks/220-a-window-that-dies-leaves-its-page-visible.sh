# title: a window that dies leaves its maintenance page visible to somebody
# origin: new in v3 — 2026-09-20, a killed window left five public sites at 503 until a human looked
check() {
# THE ONE THING THAT DOES NOT EXPIRE BY ITSELF.
#
# On 2026-09-20 an update window was killed outright while it was
# measuring — the kind of death that carries no signal a process can
# handle — so its exit trap never ran.
#
# Three of the four things it had changed about the machine came back
# anyway: the silences it raised EXPIRE on their own, which is exactly
# why they are given an expiry, and Jenkins and the backup clock were
# put back by other means. The maintenance page has no expiry. Five
# public sites answered 503 until somebody happened to look at them.
#
# So the fact that a page is up has to survive the process that raised
# it, be DERIVED from what the window wrote rather than from a flag
# beside it that could disagree the morning after, and reach somebody
# who is not staring at a terminal. All three are driven here over
# journals built on the spot, without a cluster.
D220=""
[[ -f "$AEGIS_ROOT/lib/aegis/window.py" ]] || { skip "there is no window machinery yet"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/220.py" ]] || { fail "check 220 has no sidecar: no journal was ever read back"; return; }

OUT220="$(python3 "$AEGIS_ROOT/verify/checks/220.py" "$AEGIS_ROOT" 2>&1)"
RC220=$?
if (( RC220 != 0 )); then
    fail "the exercise of check 220 itself failed (rc $RC220): $OUT220"
    return
fi
SCOPE220=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE220="${hit#SCOPE: }" ;;
        *)       D220="$D220 $hit;" ;;
    esac
done <<< "$OUT220"

printf '    %s\n' "${SCOPE220:-the scope was not reported}"
if [[ -n "$D220" ]]; then
    fail "a window can die with the page up and nobody be told:$D220"
else
    pass "the journal alone says whether the page came down, «update status» reports it as a failure with the command to undo it, and the metrics carry it to the alert that reaches a phone ($SCOPE220)"
fi
}
