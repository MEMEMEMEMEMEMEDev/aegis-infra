# title: retome de la 80 NO re-buildea si ya hay firma válida (P1.8 in-VM)
# origen: verify-static.sh (v2) ══ 53
check() {
# cada retome costaba ~10 min de build firmado innecesario:
F80_J53="$(sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/80-supply-chain.sh" \
    | nc)"
D53=""
echo "$F80_J53" | grep -qi 'docker-content-digest' \
    || D53="$D53 el digest no sale del manifest del registry;"
echo "$F80_J53" | grep -q 'build omitido' \
    || D53="$D53 sin camino de skip del build;"
L_SKIP="$(grep -in 'docker-content-digest' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
L_BLD="$(grep -n 'jenkins_next_build hello-aegis' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
{ [[ -n "$L_SKIP" && -n "$L_BLD" ]] && (( L_SKIP < L_BLD )); } \
    || D53="$D53 el check de firma-ya-válida no está ANTES del disparo del build (skip=$L_SKIP build=$L_BLD);"
echo "$F80_J53" | grep -q 'gate "firma-verificada-real"' \
    || D53="$D53 el gate firma-verificada-real desapareció (debe correr TAMBIÉN en el skip);"
if [[ -n "$D53" ]]; then fail "idempotencia de retome:$D53"
else pass "la 80 verifica el último tag del registry antes de re-buildear; el gate de firma corre siempre"; fi
}
