# dientes del check 012a — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE 'VERIFICAR-ANTES-DE-HETZNER' "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml" > "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml.diente" \
        && mv "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml.diente" "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml"; }
