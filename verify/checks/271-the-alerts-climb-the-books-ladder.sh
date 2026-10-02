# title: the alerts climb the books' ladder: debt is a daily reminder, due soon a warning, overdue and exploited critical, each saying what to do
# origin: new in v3 — 2026-10-02, plan/21 stage 8: one alert (ImageWithFixableVulns) turned every finding into the same warning, debt the platform let in on purpose included
check() {
D271=""
[[ -f "$AEGIS_ROOT/verify/checks/271.py" ]] || { fail "check 271 has no sidecar"; return; }
OUT271="$(python3 "$AEGIS_ROOT/verify/checks/271.py" "$AEGIS_ROOT" 2>&1)"
RC271=$?
(( RC271 == 0 )) || { fail "the exercise of check 271 itself failed (rc $RC271): ${OUT271:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE271="${hit#SCOPE: }" ;;
        *)       D271="$D271 $hit;" ;;
    esac
done <<< "$OUT271"
printf '    %s\n' "${SCOPE271:-the scope was not reported}"
if [[ -n "$D271" ]]; then
    fail "the ladder is broken:$D271"
else
    pass "four rungs over the states ledger.sh emits, each with its severity and its command, the daily cadence on alertmanager's route, the exploited one immediate (${SCOPE271})"
fi
}
