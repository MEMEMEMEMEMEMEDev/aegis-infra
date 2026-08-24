# title: same-commit: guards ESTRUCTURALES, nunca grep textual (H4 #13, SISTÉMICO)
# origen: verify-static.sh (v2) ══ 41
check() {
# el grep -q por NOMBRE matcheaba el COMENTARIO que documenta el
# patrón → la entry jamás se agregaba → recurso huérfano (2 en vivo:
# CR del IU + regcred del IU; 2 latentes: cosign + policy). Regla:
# todo guard sobre listas YAML usa yaml_lists_file (entry real) y
# VERIFICA el resultado con gate — || true no traga pasos:
D41=""
grep -q '^yaml_lists_file()' "$LIBS/common.sh" \
    || D41="$D41 falta yaml_lists_file en common.sh;"
BAD41="$(grep -rn 'grep -q' "$PHASES/" \
    | nc_hits \
    | grep -E "grep -q ['\"][^'\"]*\.yaml['\"]" || true)"
[[ -n "$BAD41" ]] && D41="$D41 grep textual sobre nombre .yaml (matchea comentarios):"$'\n'"$BAD41"
N_USES="$(grep -rh 'yaml_lists_file' "$PHASES/" | grep -vcE '^\s*#')"
# DOS same-commit y no cuatro desde #59, con dos usos cada uno (guard +
# gate). Se fueron los dos del Image Updater: el de la fase 40, que
# agregaba su regcred a la lista del generador, y el de la 70, que
# agregaba su CR al kustomization. Quedan los de la fase 80: la clave de
# cosign y la ClusterPolicy de firma.
(( N_USES >= 4 )) || D41="$D41 yaml_lists_file usado $N_USES veces (esperado >=4: guard+gate en los 2 same-commit);"
if [[ -n "$D41" ]]; then fail "same-commit frágil:$D41"
else pass "guards de same-commit estructurales (yaml_lists_file x$N_USES) y con gate de resultado"; fi
}
