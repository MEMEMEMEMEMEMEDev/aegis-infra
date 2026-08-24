# titulo: fases que mutan el repo de plataforma SINCRONIZAN antes (CR-6 in-VM)
# origen: verify-static.sh (v2) ══ 52
check() {
# Enfermedad D (estado dual git): un fix manual en GitHub durante un
# retome deja el clone local detrás y el siguiente push pisa/choca.
D52=""
PRS_BODY="$(body_of platform_repo_sync "$LIBS/common.sh")"
[[ -n "$PRS_BODY" ]] || D52="$D52 falta platform_repo_sync en common.sh;"
echo "$PRS_BODY" | grep -q -- '--ff-only' \
    || D52="$D52 el sync no es ff-only (un merge automático decidiría solo);"
echo "$PRS_BODY" | grep -q 'DIVERGIÓ' \
    || D52="$D52 sin muerte explícita en divergencia;"
# TODA fase que muta el repo (git -C "$PLATFORM_DIR" en línea
# no-comentario) debe llamar al sync — dinámico, cubre fases futuras:
for ph in "$AEGIS_ROOT"/init/phases/*.sh; do
    PH_NC="$(nc "$ph")"
    if echo "$PH_NC" | grep -q 'git -C "\$PLATFORM_DIR"'; then
        # la fase 12 SIEMBRA el repo (crea el remoto, push --force
        # deliberado) — el sync no aplica al nacimiento:
        [[ "$(basename "$ph")" == 12-* ]] && continue
        echo "$PH_NC" | grep -q '^platform_repo_sync$' \
            || D52="$D52 $(basename "$ph") muta el repo sin platform_repo_sync;"
    fi
done
if [[ -n "$D52" ]]; then fail "estado dual git:$D52"
else pass "toda fase que muta plataforma sincroniza primero (ff-only, divergencia = parar)"; fi
}
