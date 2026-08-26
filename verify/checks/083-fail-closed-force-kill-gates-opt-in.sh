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
# What matters is that the two gates LEAVE A RECORD when they are not
# exercised, not which word the record uses. Demanding the literal
# `skipped` is what made this check red on 2026-08-26, when the phase
# moved to the shared gate_no_subject helper and its word: a check tied
# to a spelling goes red over a correct artifact — class C15, already
# noted twice in this tree.
echo "$F80FC" | grep -Eq 'gate_no_subject|_gate_record[^\n]*failclosed' \
    || D83="$D83 the gates that are not exercised leave no record (silent — EV-08);"
echo "$F80FC" | grep -q 'failed calling webhook' \
    || D83="$D83 it does not assert that the rejection came from the downed webhook (a false fail-closed from PSS/quota);"
echo "$F80FC" | grep -q 'failclosed-argocd-admite' \
    || D83="$D83 the gate proving that argocd ADMITS is missing (bounded blast radius);"
if [[ -n "$D83" ]]; then fail "failclosed:$D83"
else pass "fail-closed: opt-in by flag, hard crash, org-canary rejects via the webhook, argocd admits, skipped recorded"; fi
}
