# title: aegis vulns and the round read the watch's books from the remote: debt inside its window is attention, past it or exploited is a failure, a silent watch is never clean
# origin: new in v3 — 2026-10-02, plan/21 stage 6: the round had two answers for what the watch found (no fixable CVE = green, any = failure), so the debt the door now lets in on purpose turned every round red
check() {
# The sidecar LOADS libexec/aegis-vulns against a real remote and a clone,
# with the watch's heartbeat injected, and RUNS the round's reader of its
# document on the shapes it emits.
D268=""
[[ -f "$AEGIS_ROOT/verify/checks/268.py" ]] || { fail "check 268 has no sidecar"; return; }
OUT268="$(python3 "$AEGIS_ROOT/verify/checks/268.py" "$AEGIS_ROOT" 2>&1)"
RC268=$?
(( RC268 == 0 )) || { fail "the exercise of check 268 itself failed (rc $RC268): ${OUT268:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE268="${hit#SCOPE: }" ;;
        *)       D268="$D268 $hit;" ;;
    esac
done <<< "$OUT268"
printf '    %s\n' "${SCOPE268:-the scope was not reported}"
if [[ -n "$D268" ]]; then
    fail "the books are misread:$D268"
else
    pass "aegis vulns reads the remote's books (rc 0 debt, 1 overdue/exploited, 2 silent/unread/unmeasured) and the round turns its document into notice, failure and COULD NOT EVALUATE (${SCOPE268})"
fi
}
