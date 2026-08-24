# dientes del check 095 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
red_1() {
    grep -vE 'cd "\$RAIZ/tofu" && "\$WRAPPER"' "$AEGIS_ROOT/libexec/aegis-vps" > "$AEGIS_ROOT/libexec/aegis-vps.diente" \
        && mv "$AEGIS_ROOT/libexec/aegis-vps.diente" "$AEGIS_ROOT/libexec/aegis-vps"
}
