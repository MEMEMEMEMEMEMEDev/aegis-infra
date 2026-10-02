# title: what tofu prints through the wrapper about a plan, an apply or a destroy carries addresses and actions, never a value of the state
# origin: new in v3 — 2026-09-30, alpha-arch: `aegis destroy` without --yes printed the tunnel's secret (random_id's values are not sensitive to its provider, and its ID is the secret itself)
check() {
D273=""
[[ -f "$AEGIS_ROOT/verify/checks/273.py" ]] || { fail "check 273 has no sidecar"; return; }
OUT273="$(python3 "$AEGIS_ROOT/verify/checks/273.py" "$AEGIS_ROOT" 2>&1)"
RC273=$?
(( RC273 == 0 )) || { fail "the exercise of check 273 itself failed (rc $RC273): ${OUT273:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE273="${hit#SCOPE: }" ;;
        *)       D273="$D273 $hit;" ;;
    esac
done <<< "$OUT273"
printf '    %s\n' "${SCOPE273:-the scope was not reported}"
if [[ -n "$D273" ]]; then
    fail "tofu prints what it should not:$D273"
else
    pass "plan, apply and destroy through tofu-apply.sh show addresses, actions, the summary and the errors with their exit code, and no value or [id=…]; output stays raw for the captures (${SCOPE273})"
fi
}
