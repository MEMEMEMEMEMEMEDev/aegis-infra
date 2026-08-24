# title: store: 'it exists but does not decrypt' ≠ 'it does not exist' (run #11)
# origin: verify-static.sh (v2) ══ 37
check() {
# a mute sops (0 chars) was treated as absence → the caller
# REGENERATED a secret already registered with third parties (worst
# case: the cosign key — it would invalidate signatures).
# restore_secret must return rc 2 in the does-not-decrypt case and the
# generators must go through store_rc_guard:
RS_BODY="$(body_of restore_secret "$LIBS/secrets.sh" \
    | nc)"
GOR_BODY="$(body_of gen_or_restore "$LIBS/secrets.sh" \
    | nc)"
GORK_BODY="$(body_of gen_or_restore_keypair "$LIBS/secrets.sh" \
    | nc)"
D37=""
echo "$RS_BODY"   | grep -q 'return 2'       || D37="$D37 restore_secret without rc-2;"
echo "$GOR_BODY"  | grep -q 'store_rc_guard' || D37="$D37 gen_or_restore without guard;"
echo "$GORK_BODY" | grep -q 'store_rc_guard' || D37="$D37 gen_or_restore_keypair without guard;"
nc "$PHASES/80-supply-chain.sh" \
    | grep -q 'store_rc_guard' || D37="$D37 phase 80 (cosign) without guard;"
if [[ -n "$D37" ]]; then fail "store does-not-decrypt treated as absence:$D37"
else pass "does-not-decrypt = rc 2 + guard in every generator (never regenerate over a mute sops)"; fi
}
