# titulo: teardown desacoplado: aegis-destroy (fin de la nube sucia) (W-10/R5)
# origen: verify-static.sh (v2) ══ 82
check() {
# La limpieza de CF estaba ACOPLADA al camino de creación (25 solo borra si
# recreás). aegis-destroy la desacopla. Invariantes:
D82=""
DS="$LIBEXEC/aegis-destroy"
if [[ -f "$DS" ]]; then
    bash -n "$DS" 2>/dev/null || D82="$D82 aegis-destroy.sh no parsea;"
    [[ -x "$DS" ]] || D82="$D82 aegis-destroy.sh no ejecutable;"
    # A14: destroy VÍA EL WRAPPER (tofu directo → destroys fantasma)
    grep -q 'tofu-apply.sh' "$DS" || D82="$D82 no usa el wrapper de tofu (A14);"
    grep -Eq '"\$TOFU".*destroy' "$DS" || D82="$D82 no destruye CF vía el wrapper;"
    # dry-run por defecto (destroy es irreversible); solo actúa con --yes
    grep -q 'YES=0'   "$DS" || D82="$D82 no es dry-run por defecto (peligroso);"
    grep -q -- '--yes' "$DS" || D82="$D82 sin gate --yes;"
    # carga la config (sin ella no sabe qué destruir)
    # La config de la instancia se llama aegis.conf y vive en $AEGIS_HOME
    # (02 §1): el destroy la lee de ahí, no del directorio del producto.
    grep -q 'AEGIS_CONF\|aegis.conf' "$DS" || D82="$D82 no carga la config del init;"
else
    D82="$D82 falta init/aegis-destroy.sh;"
fi
if [[ -n "$D82" ]]; then fail "teardown:$D82"
else pass "aegis-destroy: CF vía wrapper, dry-run+--yes, config cargada (nube sucia desacoplada)"; fi
}
