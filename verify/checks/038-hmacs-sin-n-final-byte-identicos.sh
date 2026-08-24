# titulo: HMACs sin \\n final — byte-idénticos en los DOS lados (corrida #12)
# origen: verify-static.sh (v2) ══ 38
check() {
# `openssl rand -hex 32 > out` deja \n; el Secret K8s lo conserva
# (byte-preserving) pero GitHub trimea → HMAC asimétrico → 400
# determinista en toda delivery. Se exige (a) el generador limpio y
# (b) la validación en la fase 15 (caza material VIEJO del store):
D38=""
GH32_BODY="$(body_of gen_hex32 "$LIBS/secrets.sh" \
    | nc)"
echo "$GH32_BODY" | grep 'openssl rand' | grep -q "tr -d '\\\\n'" \
    || D38="$D38 gen_hex32 emite \\n (openssl sin tr -d);"
F15_NC="$(nc "$FASES/15-terceros.sh")"
echo "$F15_NC" | grep -q 'assert_no_newline "\$HMAC_ARGO"' \
    && echo "$F15_NC" | grep -q 'assert_no_newline "\$HMAC_JENK"' \
    || D38="$D38 fase 15 sin assert_no_newline sobre los HMAC (store viejo pasaría);"
if [[ -n "$D38" ]]; then fail "HMAC con \\n:$D38"
else pass "gen_hex32 sin \\n + fase 15 valida ambos HMAC (incluye restaurados del store)"; fi
}
