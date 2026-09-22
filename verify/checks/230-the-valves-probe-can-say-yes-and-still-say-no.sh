# title: the valve's probe can say YES on a healthy cluster, and still say NO on a dead one
# origin: new in v3 — 2026-09-22, phase 20 withdrew a working reservation because its probe ran before the kubeconfig existed
check() {
# `wait_for ... _k3s_api_answers` is the valve that rolls the node's
# reservation back if k3s does not return. A probe that cannot answer
# YES turns that valve into a switch that disables the feature on a
# timer — which is what it did on the first cloud instance, three
# minutes after the API was already serving. Driven in 230.py.
D230=""
[[ -f "$AEGIS_ROOT/verify/checks/230.py" ]] || { fail "check 230 has no sidecar"; return; }
OUT230="$(python3 "$AEGIS_ROOT/verify/checks/230.py" "$AEGIS_ROOT" 2>&1)"
RC230=$?
(( RC230 == 0 )) || { fail "the scan of check 230 itself failed (rc $RC230): ${OUT230:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE230="${hit#SCOPE: }" ;;
        *)       D230="$D230 $hit;" ;;
    esac
done <<< "$OUT230"
printf '    %s\n' "${SCOPE230:-the scope was not reported}"
if [[ -n "$D230" ]]; then
    fail "the valve's probe still cannot do its job:$D230"
else
    pass "the probe answers YES on a healthy cluster before ~/.kube/config exists, falls back to the user's kubeconfig, and still answers NO when the API is down (${SCOPE230})"
fi
}
