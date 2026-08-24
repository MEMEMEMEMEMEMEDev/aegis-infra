# title: D11 — cero creación manual en paneles web en las fases
# origen: verify-static.sh (v2) ══ 15, parte b — partida en v3
check() {
PANEL="$(grep -rn 'profile/api-tokens\|settings/keys\|settings/tokens\|Developer settings' "$PHASES" || true)"
if [[ -n "$PANEL" ]]; then fail "instrucciones de panel web en fases:"$'\n'"$PANEL"
else pass "cero creación manual en paneles (fases)"; fi
}
