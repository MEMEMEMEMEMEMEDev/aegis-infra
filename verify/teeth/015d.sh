# dientes del check 015d — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE 'gen_or_restore' "$AEGIS_ROOT/lib/secrets.sh" > "$AEGIS_ROOT/lib/secrets.sh.diente" \
        && mv "$AEGIS_ROOT/lib/secrets.sh.diente" "$AEGIS_ROOT/lib/secrets.sh"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/lib/secrets.sh"; }
