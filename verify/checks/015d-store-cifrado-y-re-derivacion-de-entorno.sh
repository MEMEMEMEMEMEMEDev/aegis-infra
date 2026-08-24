# titulo: D11 — el store cifrado y la re-derivación de entorno existen
# origen: verify-static.sh (v2) ══ 15, parte d — partida en v3
check() {
# Sin store, cada re-corrida regenera credenciales y el desatendido
# deja de ser idempotente (bug 6).
D15D=""
grep -q 'gen_or_restore' "$LIBS/secrets.sh"  || D15D="$D15D falta gen_or_restore en secrets.sh;"
grep -q 'phase_env'      "$LIBEXEC/aegis-init" || D15D="$D15D falta phase_env en aegis-init;"
if [[ -n "$D15D" ]]; then fail "store/entorno:$D15D"
else pass "store cifrado + re-derivación de entorno presentes"; fi
}
