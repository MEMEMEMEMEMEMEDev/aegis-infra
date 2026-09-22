# title: the owner's deploy-key policy is asked in phase 00, not discovered in phase 15
# origin: new in v3 — 2026-09-22, the first cloud instance died in phase 15 with «Deploy keys are disabled for this repository»
check() {
# A GitHub ORGANIZATION forbids deploy keys by default, and aegis asks
# for the first one in phase 15 — after two repositories exist and two
# Cloudflare tokens have been minted. ArgoCD and Jenkins read the repos
# with those keys: without them there is no platform. The question
# belongs where the run can still stop having touched nothing.
D229=""
[[ -f "$AEGIS_ROOT/verify/checks/229.py" ]] || { fail "check 229 has no sidecar"; return; }
OUT229="$(python3 "$AEGIS_ROOT/verify/checks/229.py" "$AEGIS_ROOT" 2>&1)"
RC229=$?
(( RC229 == 0 )) || { fail "the scan of check 229 itself failed (rc $RC229): ${OUT229:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE229="${hit#SCOPE: }" ;;
        *)       D229="$D229 $hit;" ;;
    esac
done <<< "$OUT229"
printf '    %s\n' "${SCOPE229:-the scope was not reported}"
if [[ -n "$D229" ]]; then
    fail "the deploy-key policy can still be discovered too late:$D229"
else
    pass "phase 00 asks the owner's deploy-key policy before anything is created, refuses an organization that forbids them with the page that changes it, and leaves a personal account alone (${SCOPE229})"
fi
}
