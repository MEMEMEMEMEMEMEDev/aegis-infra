# title: a webhook delivery is waited for the way GitHub delivers: a failed one is re-delivered, a 400 stops at once, an old 2xx never counts
# origin: new in v3 — 2026-10-12, the Ubuntu lab VM lost phase 35 to a redelivery that hit a 502 four seconds after cloudflared connected, read again for 180s and never re-sent
check() {
D281=""
[[ -f "$AEGIS_ROOT/verify/checks/281.py" ]] || { fail "check 281 has no sidecar"; return; }
OUT281="$(python3 "$AEGIS_ROOT/verify/checks/281.py" "$AEGIS_ROOT" 2>&1)"
RC281=$?
(( RC281 == 0 )) || { fail "the exercise of check 281 itself failed (rc $RC281): ${OUT281:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE281="${hit#SCOPE: }" ;;
        *)       D281="$D281 $hit;" ;;
    esac
done <<< "$OUT281"
printf '    %s\n' "${SCOPE281:-the scope was not reported}"
if [[ -n "$D281" ]]; then
    fail "a webhook delivery is waited for in a way that cannot heal, or that an old answer satisfies:$D281"
else
    pass "phases 35 and 60 wait through one helper: a failed delivery is re-delivered at a bounded pace, a 400 stops at once, only a delivery newer than the one each phase marked counts (${SCOPE281})"
fi
}
