# titulo: las cuatro funciones de log rutean a stderr (definición)
# origen: verify-static.sh (v2) ══ 14, parte a — partida en v3
check() {
# Si un log vuelve a stdout, toda función gen_* capturada con $() se
# contamina — el bug FATAL de la validación #1: el header pegado al
# valor rompió la ceremonia de la age key.
LOGDEF_BAD="$(grep -E '^log_(info|ok|warn|error)\(\)' "$LIBS/common.sh" | grep -v '>&2' || true)"
if [[ -n "$LOGDEF_BAD" ]]; then fail "log_* SIN >&2:"$'\n'"$LOGDEF_BAD"
else pass "log_* rutean a stderr (definición)"; fi
}
