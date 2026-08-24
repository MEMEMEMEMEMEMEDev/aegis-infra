# title: HMACs with no trailing \\n — byte-identical on BOTH sides (run #12)
# origin: verify-static.sh (v2) ══ 38
check() {
# `openssl rand -hex 32 > out` leaves a \n; the K8s Secret preserves it
# (byte-preserving) but GitHub trims it → asymmetric HMAC →
# deterministic 400 on every delivery. Two things are demanded: (a) a
# clean generator and (b) the validation in phase 15 (it hunts down OLD
# material from the store):
D38=""
GH32_BODY="$(body_of gen_hex32 "$LIBS/secrets.sh" \
    | nc)"
echo "$GH32_BODY" | grep 'openssl rand' | grep -q "tr -d '\\\\n'" \
    || D38="$D38 gen_hex32 emits \\n (openssl without tr -d);"
F15_NC="$(nc "$PHASES/15-third-parties.sh")"
echo "$F15_NC" | grep -q 'assert_no_newline "\$HMAC_ARGO"' \
    && echo "$F15_NC" | grep -q 'assert_no_newline "\$HMAC_JENK"' \
    || D38="$D38 phase 15 without assert_no_newline over the HMACs (an old store would pass);"
if [[ -n "$D38" ]]; then fail "HMAC with \\n:$D38"
else pass "gen_hex32 without \\n + phase 15 validates both HMACs (including the ones restored from the store)"; fi
}
