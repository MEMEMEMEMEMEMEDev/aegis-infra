# title: --from RE-EJECUTA la fase nombrada aunque tenga marker (corrida #11)
# origen: verify-static.sh (v2) ══ 34
check() {
# --from 15 con marker previo saltaba la fase pedida por nombre → el
# recurso externo borrado fuera del init (webhook) nunca se recreó.
# Se exige la mecánica real en líneas no-comentario: la rama --from
# setea force_run=true y el skip por is_done lo consulta:
INIT_NC34="$(nc "$LIBEXEC/aegis-init")"
if echo "$INIT_NC34" | grep -q 'force_run=true' \
   && echo "$INIT_NC34" | grep 'is_done "\$name"' | grep -q 'force_run'; then
    pass "--from fuerza la re-ejecución de la fase nombrada (marker no la salta)"
else
    fail "aegis-init.sh: la fase de --from puede ser saltada por su marker (corrida #11: webhook borrado nunca recreado)"
fi
}
