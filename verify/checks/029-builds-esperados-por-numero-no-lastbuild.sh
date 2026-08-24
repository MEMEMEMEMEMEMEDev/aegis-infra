# titulo: builds esperados por NÚMERO, no lastBuild (carrera #9)
# origen: verify-static.sh (v2) ══ 29
check() {
# tras un disparo, lastBuild sigue siendo el ANTERIOR ~5-10s: leerlo
# = clase bug C. TODO jenkins_wait_build en fases debe llevar el 3er
# arg (capturado con jenkins_next_build ANTES del disparo), y ninguna
# fase debe consultar lastBuild directo:
W29=""
# a) jenkins_wait_build con solo 2 args (job + timeout, sin build):
# filtro de comentarios sobre salida de grep -rn = prefijo
# archivo:línea: (el ^\s*# original NUNCA filtraba — lo destapó un
# comentario de la fase 60 en sesión 19; mismo patrón que 29b):
BAD_WAIT="$(grep -rn 'jenkins_wait_build [a-z]' "$FASES/" \
    | nc_hits \
    | grep -vE 'jenkins_wait_build [^ ]+ [0-9]+ ' || true)"
[[ -n "$BAD_WAIT" ]] && W29="$W29 wait sin build_n:"$'\n'"$BAD_WAIT"
# b) lastBuild directo en fases — USO real es un componente de path
#    de la API (/lastBuild), no la palabra en un comentario trailing
#    (mención ≠ uso — el teeth lo reveló):
BAD_LAST="$(grep -rn '/lastBuild' "$FASES/" \
    | nc_hits || true)"
[[ -n "$BAD_LAST" ]] && W29="$W29 lastBuild directo:"$'\n'"$BAD_LAST"
if [[ -n "$W29" ]]; then fail "carrera lastBuild:$W29"
else pass "todo build se espera por número específico (jenkins_next_build)"; fi
}
