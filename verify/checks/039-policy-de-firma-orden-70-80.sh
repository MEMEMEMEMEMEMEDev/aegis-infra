# title: policy de firma: orden 70/80 como MECANISMO (corrida #12)
# origen: verify-static.sh (v2) ══ 39
check() {
# La App kyverno-policies es automated: cualquier policy listada
# estática entra viva desde la fase 35 — con __COSIGN_PUB__
# placeholder la evaluación crashea y failurePolicy=Fail rechaza el
# canary de la 70 aunque el action sea Audit. Invariante: el
# kustomization NO lista el ClusterPolicy (nace resources: []) y la
# fase 80 lo agrega en el mismo commit que inyecta la pub:
D39=""
KPK="$P/k8s/base/kyverno-policies/kustomization.yaml"
if [[ ! -f "$KPK" ]]; then
    D39="$D39 falta kustomization.yaml (directory-app aplica TODO el dir);"
else
    KPK_RES="$(python3 -c "
import yaml,sys
print(' '.join((yaml.safe_load(open('$KPK')) or {}).get('resources') or []))")"
    grep -q 'clusterpolicy' <<< "$KPK_RES" \
        && D39="$D39 el ClusterPolicy está listado ESTÁTICO (entra vivo pre-80);"
fi
F80_NC="$(nc "$PHASES/80-supply-chain.sh")"
echo "$F80_NC" | grep -q 'kyverno-policies/kustomization.yaml' \
    && echo "$F80_NC" | grep -q 'clusterpolicy-require-aegis-signature.yaml' \
    || D39="$D39 la fase 80 no agrega el policy al kustomization (quedaría huérfano);"
[[ -f "$P/k8s/base/kyverno-policies/clusterpolicy-require-aegis-signature.yaml" ]] \
    || D39="$D39 el archivo del policy no existe;"
if [[ -n "$D39" ]]; then fail "orden 70/80 roto:$D39"
else pass "el policy de firma NO existe hasta que la fase 80 lo agrega (runtime-entry)"; fi
}
