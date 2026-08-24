# title: gates que no pueden fallar (tautologías)
# origen: verify-static.sh (v2) ══ 8
check() {
# heurística: la línea/comando de un gate no debe terminar tragando
# el resultado (|| true, ; true) — un gate así no es un gate.
TAUT="$(grep -rn 'gate ' "$PHASES" "$AEGIS_ROOT/init/lib" \
    | grep -E '\|\|\s*true|;\s*true\s*"?$' || true)"
if [[ -n "$TAUT" ]]; then fail "gates tautológicos:"$'\n'"$TAUT"
else pass "sin gates tautológicos"; fi
}
