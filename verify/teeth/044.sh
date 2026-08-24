# teeth of check 044 — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# takes out of the artifact exactly what the check claims to measure
red_1() {
    grep -vE 'registry_cluster_ip }} registry.registry-system.svc.cluster.local' "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml" > "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml.tooth" \
        && mv "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml.tooth" "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml"; }
