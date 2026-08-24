# dientes del check 024 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE 'resolv-conf: /run/systemd/resolve/resolv.conf' "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml" > "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml.diente" \
        && mv "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml.diente" "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml"; }
