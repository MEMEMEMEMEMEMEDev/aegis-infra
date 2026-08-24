# titulo: inyecciones multi-línea SOLO via inject_placeholder (CR-1/CR-2 #14)
# origen: verify-static.sh (v2) ══ 48
check() {
# La familia hermana del H4 aplicada a las INYECCIONES: replace()
# global volcaba el PEM en el comentario que documentaba el
# placeholder (CR-1: YAML top-level roto) y next() tomaba el indent
# de la PRIMERA ocurrencia — un comentario (CR-2: block scalar roto).
D48=""
# (a) el helper existe y tiene las 4 defensas:
IP_BODY="$(body_of inject_placeholder "$LIBS/common.sh")"
[[ -n "$IP_BODY" ]] || D48="$D48 falta inject_placeholder en common.sh;"
echo "$IP_BODY" | grep -q 'startswith("#")' \
    || D48="$D48 el helper NO filtra comentarios;"
echo "$IP_BODY" | grep -q 'len(hits) != 1' \
    || D48="$D48 el helper NO exige ocurrencia única;"
echo "$IP_BODY" | grep -q 'safe_load_all' \
    || D48="$D48 el helper NO valida el YAML resultante;"
grep -q '^placeholder_pending()' "$LIBS/common.sh" \
    || D48="$D48 falta placeholder_pending (guard de idempotencia);"
# (b) ninguna fase inyecta a mano (replace() de python sobre un
# placeholder = el camino que rompió la #14); fase 80 usa el helper
# para SUS DOS placeholders de clase-generado:
BAD48="$(grep -rn 'replace("__' "$FASES" || true)"
[[ -n "$BAD48" ]] && D48="$D48 replace() manual de placeholder:"$'\n'"$BAD48"
N_IP="$(grep -c 'inject_placeholder ' "$FASES/80-supply-chain.sh" || true)"
(( N_IP >= 2 )) || D48="$D48 fase 80 con $N_IP usos de inject_placeholder (esperados >=2: COSIGN_PUB + AEGIS_CA_PEM);"
# (c) NINGÚN comentario de platform/ escribe un placeholder de
# clase-generado literal (el helper los ignora, pero la defensa es
# doble — un comentario con el literal fue LA bomba de CR-1). Cubre
# también los 3 generados de la fase 85 (OBS_CA_PEM + hashes ntfy):
BAD48C="$(grep -rn '__COSIGN_PUB__\|__AEGIS_CA_PEM__\|__AGE_PUBLIC__\|__OBS_CA_PEM__\|__OBS_NTFY_OPERADOR_HASH__\|__OBS_NTFY_PUENTE_HASH__' "$P" \
    --include='*.yaml' --include='*.yml' \
  | grep -E ':[0-9]+:\s*#|#.*__(COSIGN_PUB|AEGIS_CA_PEM|AGE_PUBLIC|OBS_CA_PEM|OBS_NTFY_OPERADOR_HASH|OBS_NTFY_PUENTE_HASH)__' || true)"
[[ -n "$BAD48C" ]] && D48="$D48 placeholder literal en comentario:"$'\n'"$BAD48C"
# (d) gate del RESULTADO tras cada inyección (regla de la familia H4):
F80_NC="$(nc "$FASES/80-supply-chain.sh")"
echo "$F80_NC" | grep -q 'cosign-pub-inyectada' \
    || D48="$D48 falta gate cosign-pub-inyectada;"
echo "$F80_NC" | grep -q 'ca-inyectado-en-kyverno' \
    || D48="$D48 falta gate ca-inyectado-en-kyverno;"
if [[ -n "$D48" ]]; then fail "inyecciones:$D48"
else pass "inyecciones via inject_placeholder (no-comentario, única, indent real, YAML validado) + gates de resultado"; fi
}
