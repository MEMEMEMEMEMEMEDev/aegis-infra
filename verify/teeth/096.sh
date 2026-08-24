# dientes del check 096 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
red_1() {
    grep -vE 'AEGIS_STATE_DIR' "$AEGIS_ROOT/libexec/aegis-init-log" > "$AEGIS_ROOT/libexec/aegis-init-log.diente" \
        && mv "$AEGIS_ROOT/libexec/aegis-init-log.diente" "$AEGIS_ROOT/libexec/aegis-init-log"
}
