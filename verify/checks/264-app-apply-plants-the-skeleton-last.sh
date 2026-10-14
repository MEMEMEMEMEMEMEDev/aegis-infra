# title: `aegis app apply` plants the skeleton after the webhook exists (its push is the first build), and `app new` tells the steps in the order that works
# origin: new in v3 — 2026-09-30, the Arch lab VM: the portfolio's skeleton was pushed before the webhook and the first build never started; app new said app apply --check before the push that makes it evaluable
check() {
# The skeleton went up before the webhook, and the steps were told out
# of order. The sidecar RUNS app apply with GitHub recorded.
D264=""
[[ -f "$AEGIS_ROOT/verify/checks/264.py" ]] || { fail "check 264 has no sidecar"; return; }
OUT264="$(python3 "$AEGIS_ROOT/verify/checks/264.py" "$AEGIS_ROOT" 2>&1)"
RC264=$?
(( RC264 == 0 )) || { fail "the exercise of check 264 itself failed (rc $RC264): ${OUT264:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE264="${hit#SCOPE: }" ;;
        *)       D264="$D264 $hit;" ;;
    esac
done <<< "$OUT264"
printf '    %s\n' "${SCOPE264:-the scope was not reported}"
if [[ -n "$D264" ]]; then
    fail "app apply or app new are out of order:$D264"
else
    pass "the skeleton is planted after the webhook and the deploy key, and app new tells push, edge, apply in that order (${SCOPE264})"
fi
}
