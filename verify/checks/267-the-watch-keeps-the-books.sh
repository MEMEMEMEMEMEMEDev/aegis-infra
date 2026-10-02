# title: the watch keeps the books: every finding of what is served, with its due date, committed to the platform repo with a fresh exploited list
# origin: new in v3 — 2026-10-02, plan/21 stage 6: the door lets findings in as debt, and nothing kept the debt with a date; the watch published counts and the exploited list it was supposed to refresh never moved
check() {
# The sidecar RUNS image-watch/ledger.sh (sh and, when present, busybox)
# on the cases that define the books, and reads the watch's stages and the
# seed's ownership table.
D267=""
[[ -f "$AEGIS_ROOT/verify/checks/267.py" ]] || { fail "check 267 has no sidecar"; return; }
OUT267="$(python3 "$AEGIS_ROOT/verify/checks/267.py" "$AEGIS_ROOT" 2>&1)"
RC267=$?
(( RC267 == 0 )) || { fail "the exercise of check 267 itself failed (rc $RC267): ${OUT267:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE267="${hit#SCOPE: }" ;;
        *)       D267="$D267 $hit;" ;;
    esac
done <<< "$OUT267"
printf '    %s\n' "${SCOPE267:-the scope was not reported}"
if [[ -n "$D267" ]]; then
    fail "the books are not kept:$D267"
else
    pass "every image looked at is a line (clean, debt, overdue, exploited, unmeasured), a dateless finding keeps its first-seen clock, and the watch commits only the books and the list (${SCOPE267})"
fi
}
