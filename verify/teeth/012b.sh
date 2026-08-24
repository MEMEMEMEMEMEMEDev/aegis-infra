# dientes del check 012b (sin espejo de chart pins en group_vars)
rojo_1() { printf '\nchart_pins:\n  traefik: "1.2.3"\n' >> "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml"; }
control_1() { printf '\n# los chart_pins viven en otro lado a propósito\n' >> "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml"; }
