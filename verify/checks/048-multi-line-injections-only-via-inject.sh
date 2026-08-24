# title: multi-line injections ONLY via inject_placeholder (CR-1/CR-2 #14)
# origin: verify-static.sh (v2) ══ 48
check() {
# The sister family of H4 applied to the INJECTIONS: a global replace()
# dumped the PEM into the comment that documented the placeholder
# (CR-1: broken top-level YAML) and next() took the indent of the FIRST
# occurrence — a comment (CR-2: broken block scalar).
D48=""
# (a) the helper exists and has the 4 defenses:
IP_BODY="$(body_of inject_placeholder "$LIBS/common.sh")"
[[ -n "$IP_BODY" ]] || D48="$D48 inject_placeholder missing from common.sh;"
echo "$IP_BODY" | grep -q 'startswith("#")' \
    || D48="$D48 the helper does NOT filter comments;"
echo "$IP_BODY" | grep -q 'len(hits) != 1' \
    || D48="$D48 the helper does NOT demand a single occurrence;"
echo "$IP_BODY" | grep -q 'safe_load_all' \
    || D48="$D48 the helper does NOT validate the resulting YAML;"
grep -q '^placeholder_pending()' "$LIBS/common.sh" \
    || D48="$D48 placeholder_pending missing (idempotence guard);"
# (b) no phase injects by hand (python replace() over a placeholder =
# the path that broke #14); phase 80 uses the helper for ITS TWO
# generated-class placeholders:
BAD48="$(grep -rn 'replace("__' "$PHASES" || true)"
[[ -n "$BAD48" ]] && D48="$D48 manual replace() of a placeholder:"$'\n'"$BAD48"
N_IP="$(grep -c 'inject_placeholder ' "$PHASES/80-supply-chain.sh" || true)"
(( N_IP >= 2 )) || D48="$D48 phase 80 with $N_IP uses of inject_placeholder (expected >=2: COSIGN_PUB + AEGIS_CA_PEM);"
# (c) NO comment in platform/ writes a generated-class placeholder as a
# literal (the helper ignores them, but the defense is double — a
# comment with the literal was THE bomb of CR-1). It also covers the 3
# generated ones of phase 85 (OBS_CA_PEM + ntfy hashes):
BAD48C="$(grep -rn '__COSIGN_PUB__\|__AEGIS_CA_PEM__\|__AGE_PUBLIC__\|__OBS_CA_PEM__\|__OBS_NTFY_OPERADOR_HASH__\|__OBS_NTFY_PUENTE_HASH__' "$P" \
    --include='*.yaml' --include='*.yml' \
  | grep -E ':[0-9]+:\s*#|#.*__(COSIGN_PUB|AEGIS_CA_PEM|AGE_PUBLIC|OBS_CA_PEM|OBS_NTFY_OPERADOR_HASH|OBS_NTFY_PUENTE_HASH)__' || true)"
[[ -n "$BAD48C" ]] && D48="$D48 literal placeholder inside a comment:"$'\n'"$BAD48C"
# (d) a gate over the RESULT after each injection (rule of the H4 family):
F80_NC="$(nc "$PHASES/80-supply-chain.sh")"
echo "$F80_NC" | grep -q 'cosign-pub-inyectada' \
    || D48="$D48 gate cosign-pub-inyectada missing;"
echo "$F80_NC" | grep -q 'ca-inyectado-en-kyverno' \
    || D48="$D48 gate ca-inyectado-en-kyverno missing;"
if [[ -n "$D48" ]]; then fail "injections:$D48"
else pass "injections via inject_placeholder (non-comment, unique, real indent, validated YAML) + result gates"; fi
}
