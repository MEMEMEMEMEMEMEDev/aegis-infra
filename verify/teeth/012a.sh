# teeth of check 012a — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# takes out of the artifact exactly what the check claims to measure
red_1() {
    grep -vE 'VERIFICAR-ANTES-DE-HETZNER' "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml" > "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml.tooth" \
        && mv "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml.tooth" "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml"; }
