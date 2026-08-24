# dientes del check 102 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE 'readlink -f' "$AEGIS_ROOT/libexec/aegis-backup" > "$AEGIS_ROOT/libexec/aegis-backup.diente" \
        && mv "$AEGIS_ROOT/libexec/aegis-backup.diente" "$AEGIS_ROOT/libexec/aegis-backup"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/lib/access.sh"; }
