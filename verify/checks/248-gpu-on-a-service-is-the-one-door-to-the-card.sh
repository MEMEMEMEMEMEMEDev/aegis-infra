# title: `gpu: true` on a service is the one door to the card, and it opens for that service only
# origin: new in v3 — 2026-09-25, the hackathon's organization needs the home GPU the day it was closed to all
check() {
# tenants-without-gpu (check 247) refuses the card to every organization.
# The contract's `gpu: true` is the way the platform hands it to ONE
# service: a label on the Namespace (which a tenant cannot write), a quota
# of one card, and the organization's sizes Policy writing the runtime
# class and the request. The policy steps aside only for that label, and
# in a granted namespace the nvidia runtime is tied to asking for the card.
D248=""
[[ -f "$AEGIS_ROOT/verify/checks/248.py" ]] || { fail "check 248 has no sidecar"; return; }
OUT248="$(python3 "$AEGIS_ROOT/verify/checks/248.py" "$AEGIS_ROOT" 2>&1)"
RC248=$?
(( RC248 == 0 )) || { fail "the scan of check 248 itself failed (rc $RC248): ${OUT248:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE248="${hit#SCOPE: }" ;;
        *)       D248="$D248 $hit;" ;;
    esac
done <<< "$OUT248"
printf '    %s\n' "${SCOPE248:-the scope was not reported}"
if [[ -n "$D248" ]]; then
    fail "the GPU grant is wrong:$D248"
else
    pass "gpu: true grants one card to one service through the Namespace label, the quota and the sizes Policy, and the policy steps aside for that label only (${SCOPE248})"
fi
}
