# title: fail-closed force-kill gates: opt-in, not silent, right reason (W-08)
# origin: verify-static.sh (v2) ══ 83
check() {
D83=""
F80FC="$(nc "$PHASES/80-supply-chain.sh")"
echo "$F80FC" | grep -q 'AEGIS_VALIDATE_FAILCLOSED' \
    || D83="$D83 the fail-closed gates are not opt-in (they would crash every bootstrap);"
echo "$F80FC" | grep -q '_failclosed_gates' \
    || D83="$D83 the _failclosed_gates function is missing;"
echo "$F80FC" | grep -q -- '--grace-period=0' \
    || D83="$D83 there is no HARD crash (--grace-period=0 --force) of the admission controller;"
echo "$F80FC" | grep -Eq '"failclosed[^"]*" skipped' \
    || D83="$D83 the skipped gates are not recorded as skipped (silent — EV-08);"
echo "$F80FC" | grep -q 'failed calling webhook' \
    || D83="$D83 it does not assert that the rejection came from the downed webhook (a false fail-closed from PSS/quota);"
echo "$F80FC" | grep -q 'failclosed-argocd-admite' \
    || D83="$D83 the gate proving that argocd ADMITS is missing (bounded blast radius);"
if [[ -n "$D83" ]]; then fail "failclosed:$D83"
else pass "fail-closed: opt-in by flag, hard crash, org-canary rejects via the webhook, argocd admits, skipped recorded"; fi
}
