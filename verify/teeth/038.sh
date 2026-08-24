# dientes del check 038 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
red_1() {
    grep -vE 'assert_no_newline "\$HMAC_ARGO"' "$AEGIS_ROOT/init/phases/15-terceros.sh" > "$AEGIS_ROOT/init/phases/15-terceros.sh.diente" \
        && mv "$AEGIS_ROOT/init/phases/15-terceros.sh.diente" "$AEGIS_ROOT/init/phases/15-terceros.sh"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/init/phases/15-terceros.sh"; }
