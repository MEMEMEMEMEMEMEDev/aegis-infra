# title: UNA sola definición de argo_sync (bug C — anti-drift)
# origen: verify-static.sh (v2) ══ 27
check() {
# Corrida #8: 5 fases definían su argo_sync local (patch + wait de
# health) → la carrera health-vs-operationState vivía replicada en
# todas. El fix del bug C es la definición CANÓNICA de common.sh
# (espera la fase TERMINAL de la operación nueva); una def local
# nueva la taparía en silencio:
SYNC_LOCAL="$(grep -rln '^argo_sync()' "$PHASES/" || true)"
SYNC_COMMON="$(grep -c '^argo_sync()' "$LIBS/common.sh" || true)"
if [[ -n "$SYNC_LOCAL" ]]; then
    fail "argo_sync REDEFINIDO local (tapa el fix del bug C):"$'\n'"$SYNC_LOCAL"
elif [[ "$SYNC_COMMON" != 1 ]]; then
    fail "argo_sync canónico ausente/duplicado en common.sh ($SYNC_COMMON)"
else
    pass "argo_sync: una sola definición (common.sh, fase-terminal-aware)"
fi
}
