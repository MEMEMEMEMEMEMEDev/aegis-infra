# title: a canary sync that died refusing the signed digest is synced again once the policy is live, before the canary gate waits
# origin: new in v3 — 2026-09-24, second cloud VM: the canary gate waited fifteen minutes for a sync ArgoCD does not retry
check() {
# ArgoCD re-attempts an automated sync only for a NEW revision. The
# canary revision carrying the signed digest was synced while Kyverno
# could not verify signatures and was denied; once Kyverno was repaired
# nobody asked again, and the gate that waits for the canary to be
# pinned to that digest timed out. Phase 80 has to notice exactly that
# failure and fire the sync itself.
D237=""
[[ -f "$AEGIS_ROOT/verify/checks/237.py" ]] || { fail "check 237 has no sidecar"; return; }
OUT237="$(python3 "$AEGIS_ROOT/verify/checks/237.py" "$AEGIS_ROOT" 2>&1)"
RC237=$?
(( RC237 == 0 )) || { fail "the scan of check 237 itself failed (rc $RC237): ${OUT237:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE237="${hit#SCOPE: }" ;;
        *)       D237="$D237 $hit;" ;;
    esac
done <<< "$OUT237"
printf '    %s\n' "${SCOPE237:-the scope was not reported}"
if [[ -n "$D237" ]]; then
    fail "the canary can wait on a sync that will never come:$D237"
else
    pass "a canary sync that failed refusing the signed digest is fired again after the policy is live and before the canary gate (${SCOPE237})"
fi
}
