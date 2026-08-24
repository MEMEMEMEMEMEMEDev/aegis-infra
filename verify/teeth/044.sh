# dientes del check 044 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE 'registry_cluster_ip }} registry.registry-system.svc.cluster.local' "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml" > "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml.diente" \
        && mv "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml.diente" "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml"; }
