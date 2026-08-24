# dientes del check 093 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE '\(\(\s*dijo\s*\)\)\s*\|\|\s*aviso' "$AEGIS_ROOT/libexec/aegis-chequeo" > "$AEGIS_ROOT/libexec/aegis-chequeo.diente" \
        && mv "$AEGIS_ROOT/libexec/aegis-chequeo.diente" "$AEGIS_ROOT/libexec/aegis-chequeo"
}
