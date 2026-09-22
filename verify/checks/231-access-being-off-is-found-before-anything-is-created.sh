# title: Cloudflare Access being off is found before anything is created, and the journey says to switch it on
# origin: new in v3 — 2026-09-22, the first cloud instance discovered Zero Trust was dormant in the middle of tofu apply
check() {
# A brand new Cloudflare account has Zero Trust dormant, and aegis puts
# the operator consoles behind Access in phases 25, 35 and 60. The API
# answers 403 «not_enabled» to every Access call, and tofu found out
# halfway through creating the edge. The question belongs before the
# apply, and the journey that prepares the account belongs in the docs.
D231=""
[[ -f "$AEGIS_ROOT/verify/checks/231.py" ]] || { fail "check 231 has no sidecar"; return; }
OUT231="$(python3 "$AEGIS_ROOT/verify/checks/231.py" "$AEGIS_ROOT" 2>&1)"
RC231=$?
(( RC231 == 0 )) || { fail "the scan of check 231 itself failed (rc $RC231): ${OUT231:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE231="${hit#SCOPE: }" ;;
        *)       D231="$D231 $hit;" ;;
    esac
done <<< "$OUT231"
printf '    %s\n' "${SCOPE231:-the scope was not reported}"
if [[ -n "$D231" ]]; then
    fail "Access being off can still be discovered too late:$D231"
else
    pass "phase 25 asks whether Access is enabled before it creates anything, names the page that enables it, and the journey tells the operator to switch it on (${SCOPE231})"
fi
}
