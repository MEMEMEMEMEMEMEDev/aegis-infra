# dientes del check 081 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
red_1() {
    grep -vE 'STATE_SECRETS' "$AEGIS_ROOT/libexec/aegis-rotate" > "$AEGIS_ROOT/libexec/aegis-rotate.diente" \
        && mv "$AEGIS_ROOT/libexec/aegis-rotate.diente" "$AEGIS_ROOT/libexec/aegis-rotate"
}
