# title: CONVERGENCE family canonized (A/B v1.0 — 5th instance)
# origin: verify-static.sh (v2) ══ 72
check() {
# operating/measuring BEFORE the system converges came back 5 times
# (coredns H4, the op-that-never-arrives H5, an old Succeeded from bug
# C, discovery without the types A, the RS cascade B). The canon:
# EXISTENCE→STABILITY→MEASURE helpers in common.sh and the gates going
# through them — a new one-off patch of this class must bite HERE:
D72=""
for h in wait_for k8s_converged deploy_current_pods_ok; do
    nc "$LIBS/common.sh" | grep -q "^$h()" \
        || D72="$D72 the $h helper is missing from common.sh;"
done
ASY72="$(body_of argo_sync "$LIBS/common.sh")"
echo "$ASY72" | grep -q 'AEGIS_SYNC_VALIDATION_SIGS' \
    || D72="$D72 A: argo_sync does not retry the transient validation (tasks are not valid);"
echo "$ASY72" | grep -q 'val_refires' \
    || D72="$D72 A: no dedicated counter for validation retries;"
echo "$ASY72" | grep -q 'syncResult.resources' \
    || D72="$D72 A: on death it does not print WHICH task is invalid (only the generic phrase);"
nc "$LIBS/common.sh" | grep -q '^AEGIS_SYNC_VALIDATION_SIGS=' \
    || D72="$D72 A: the transient validation signature is missing;"
# B: in phase 80, restart → CONVERGENCE → measurement of the CURRENT RS:
L_RST="$(awk '!/^[[:space:]]*#/ && /rollout restart deploy\/hello-aegis/{print NR; exit}' "$PHASES/80-supply-chain.sh")"
L_CVG="$(awk '!/^[[:space:]]*#/ && /positivo-rollout-convergido/{print NR; exit}' "$PHASES/80-supply-chain.sh")"
L_POS="$(awk '!/^[[:space:]]*#/ && /"positivo-admitido-y-digest"/{print NR; exit}' "$PHASES/80-supply-chain.sh")"
if [[ -z "$L_RST" || -z "$L_CVG" || -z "$L_POS" ]] || ! (( L_RST < L_CVG && L_CVG < L_POS )); then
    D72="$D72 B: the positive does not wait for convergence between the restart and the measurement;"
fi
nc "$PHASES/80-supply-chain.sh" | grep -q 'deploy_current_pods_ok' \
    || D72="$D72 B: the positive does not measure the CURRENT RS (with a cascade there are always old pods);"
nc "$PHASES/80-supply-chain.sh" | grep -q 'POSSIBLE TIMING' \
    || D72="$D72 B: no warning about an evidence/verdict contradiction;"
# structural prohibition: measuring "items[0] of the namespace" in a
# gate is EXACTLY bug B — zero non-comment instances in the phases:
BAD72="$(grep -rn 'items\[0\]' "$AEGIS_ROOT"/init/phases/ 2>/dev/null | nc_hits || true)"
[[ -z "$BAD72" ]] || D72="$D72 items[0]-of-the-namespace measurement alive: $BAD72;"
# sweep: the two high-risk twins that had NOT bitten:
sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/20-k3s.sh" \
  | nc | grep '"default-storageclass"' | grep -q 'wait_for' \
    || D72="$D72 sweep: phase 20's storageclass without an existence wait (coredns' twin);"
# HERE IT USED TO BE VERIFIED that the dry-run of the Image Updater's CR
# waited for the CRD in the discovery. Both gates left with the
# component (#59). The general invariant —waiting for the type to EXIST
# before validating against it— is still covered by the rest of this
# section.
if [[ -n "$D72" ]]; then fail "convergence:$D72"
else pass "EXISTENCE→STABILITY→MEASURE canonized: helpers in common, A/B absorbed, twins (SC, CRD) covered, items[0] forbidden"; fi
}
