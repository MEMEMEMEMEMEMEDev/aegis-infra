# teeth of check 012b (no chart pins mirror in group_vars)
red_1() { printf '\nchart_pins:\n  traefik: "1.2.3"\n' >> "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml"; }
control_1() { printf '\n# the chart_pins live somewhere else on purpose\n' >> "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml"; }
