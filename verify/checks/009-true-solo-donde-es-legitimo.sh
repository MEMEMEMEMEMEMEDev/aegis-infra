# title: '|| true' solo donde es legítimo
# origen: verify-static.sh (v2) ══ 9
check() {
# legítimos: git commit (nada que commitear), limpieza best-effort,
# greps de inventario. Ilegítimos: sobre secretos/gates/aplicación.
BAD="$(grep -rn '|| true' "$PHASES" \
    | nc_hits \
    | grep -vE 'git .*commit|--no-verify|log_info|kustomization.yaml 2>/dev/null' \
    | grep -vE '>&2 \|\| true' \
    | grep -vE '\|\| true\)"$' \
    || true)"
# ('>&2 || true' = dump de evidencia best-effort a stderr en un
#  camino de diagnóstico; '|| true)"' = captura $(...) con fallback
#  vacío que un [[ ]] posterior evalúa explícitamente — ninguno
#  traga el resultado de un gate)
if [[ -n "$BAD" ]]; then fail "'|| true' sospechosos:"$'\n'"$BAD"
else pass "'|| true' auditados (solo commits idempotentes)"; fi
}
