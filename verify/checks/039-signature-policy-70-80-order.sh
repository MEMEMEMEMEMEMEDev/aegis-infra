# title: signature policy: the 70/80 order as a MECHANISM (run #12)
# origin: verify-static.sh (v2) ══ 39
check() {
# The kyverno-policies App is automated: any policy listed statically
# goes live from phase 35 on — with __COSIGN_PUB__ as a placeholder
# the evaluation crashes and failurePolicy=Fail rejects the canary of
# phase 70 even though the action is Audit. Invariant: the
# kustomization does NOT list the ClusterPolicy (it is born with
# resources: []) and phase 80 adds it in the same commit that injects
# the pub:
D39=""
KPK="$P/k8s/base/kyverno-policies/kustomization.yaml"
if [[ ! -f "$KPK" ]]; then
    D39="$D39 kustomization.yaml is missing (directory-app applies the WHOLE dir);"
else
    KPK_RES="$(python3 -c "
import yaml,sys
print(' '.join((yaml.safe_load(open('$KPK')) or {}).get('resources') or []))")"
    grep -q 'clusterpolicy' <<< "$KPK_RES" \
        && D39="$D39 the ClusterPolicy is listed STATICALLY (it goes live pre-80);"
fi
F80_NC="$(nc "$PHASES/80-supply-chain.sh")"
echo "$F80_NC" | grep -q 'kyverno-policies/kustomization.yaml' \
    && echo "$F80_NC" | grep -q 'clusterpolicy-require-aegis-signature.yaml' \
    || D39="$D39 phase 80 does not add the policy to the kustomization (it would be left orphaned);"
[[ -f "$P/k8s/base/kyverno-policies/clusterpolicy-require-aegis-signature.yaml" ]] \
    || D39="$D39 the policy file does not exist;"
if [[ -n "$D39" ]]; then fail "70/80 order broken:$D39"
else pass "the signature policy does NOT exist until phase 80 adds it (runtime-entry)"; fi
}
