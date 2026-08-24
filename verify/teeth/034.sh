# dientes del check 034 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
red_1() {
    grep -vE 'force_run=true' "$AEGIS_ROOT/libexec/aegis-init" > "$AEGIS_ROOT/libexec/aegis-init.diente" \
        && mv "$AEGIS_ROOT/libexec/aegis-init.diente" "$AEGIS_ROOT/libexec/aegis-init"
}
