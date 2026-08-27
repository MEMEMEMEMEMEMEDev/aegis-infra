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
    # The rc of the reader is INSPECTED. Until 2026-08-24 it was not:
    # if the python failed —a malformed kustomization, a missing pyyaml—
    # KPK_RES came back empty, the `grep -q` found nothing, and this
    # sub-check reported healthy. Silence as success, which is the exact
    # shape `not-evaluable` exists to kill. A sub-check that cannot run
    # has to SAY it could not run.
    if ! KPK_RES="$(python3 -c "
import yaml,sys
print(' '.join((yaml.safe_load(open('$KPK')) or {}).get('resources') or []))" 2>/dev/null)"; then
        D39="$D39 could not READ $KPK (malformed kustomization, or no pyyaml) — this sub-check did not run;"
    elif grep -q 'clusterpolicy' <<< "$KPK_RES"; then
        D39="$D39 the ClusterPolicy is listed STATICALLY (it goes live pre-80);"
    fi
fi
F80_NC="$(nc "$PHASES/80-supply-chain.sh")"
echo "$F80_NC" | grep -q 'kyverno-policies/kustomization.yaml' \
    && echo "$F80_NC" | grep -q 'clusterpolicy-require-aegis-signature.yaml' \
    || D39="$D39 phase 80 does not add the policy to the kustomization (it would be left orphaned);"
[[ -f "$P/k8s/base/kyverno-policies/clusterpolicy-require-aegis-signature.yaml" ]] \
    || D39="$D39 the policy file does not exist;"
# The other half of the order (2026-08-27, second init over a host that
# had carried an instance): a platform/ from a previous cluster already
# lists the policy, and root would sync it in phase 35 with a Kyverno
# that cannot reach the registry yet. Phase 35 turns it OFF; 80 turns it
# on again:
F35_NC="$(nc "$PHASES/35-gitops.sh")"
echo "$F35_NC" | grep -q 'kyverno-policies/kustomization.yaml' \
    && echo "$F35_NC" | grep -q '"resources: \[\]"' \
    && echo "$F35_NC" | grep -q 'politica-apagada-hasta-80' \
    || D39="$D39 phase 35 does not turn the policy OFF on a re-init (a platform/ from a previous cluster would enforce before Kyverno can verify);"
if [[ -n "$D39" ]]; then fail "70/80 order broken:$D39"
else pass "the signature policy does NOT exist until phase 80 adds it (runtime-entry)"; fi
}
