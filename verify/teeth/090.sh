# dientes del check 090 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE 'cloudflareaccess\.com' "$AEGIS_ROOT/lib/access.sh" > "$AEGIS_ROOT/lib/access.sh.diente" \
        && mv "$AEGIS_ROOT/lib/access.sh.diente" "$AEGIS_ROOT/lib/access.sh"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/lib/access.sh"; }
