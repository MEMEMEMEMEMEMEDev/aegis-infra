# titulo: las fases corren con errexit VIVO (F-A #15 — el misterio del set -e)
# origen: verify-static.sh (v2) ══ 59
check() {
# `if ( source fase )` pone la fase en contexto de condición → bash
# IGNORA errexit adentro y el set -e interno es IMPOTENTE (semántica
# documentada) → NINGÚN fallo no-gate cortó jamás (#9 push caído,
# #15 argo_sync Error seguido de gate verde). El orquestador debe
# correr la fase como comando PLANO y capturar el rc con errexit
# del padre apagado:
D59=""
ORQ="$LIBEXEC/aegis-init"
nc "$ORQ" | grep -q 'if ( source' \
    && D59="$D59 la fase corre en condición de if (errexit muerto adentro);"
nc "$ORQ" | grep -qE '\( source "\$p" \)( \|\||\s*&&)' \
    && D59="$D59 el subshell de la fase está en lista ||/&& (mismo contexto ignorado);"
ORQ_NC="$(nc "$ORQ")"
echo "$ORQ_NC" | grep -q '( source "$p" )' \
    || D59="$D59 no encuentro el subshell plano de la fase;"
echo "$ORQ_NC" | grep -B2 '( source "$p" )' | grep -q 'set +e' \
    || D59="$D59 falta set +e del padre antes del subshell (con -e del padre, el rc nunca se captura);"
echo "$ORQ_NC" | grep -A1 '( source "$p" )' | grep -q '_phase_rc=\$?' \
    || D59="$D59 el rc de la fase no se captura;"
if [[ -n "$D59" ]]; then fail "errexit de fases:$D59"
else pass "fases como comando plano + rc capturado — set -e interno por fin EFECTIVO"; fi
}
