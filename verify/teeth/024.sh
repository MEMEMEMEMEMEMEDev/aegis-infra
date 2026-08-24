# teeth of check 024 — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# takes out of the artifact exactly what the check claims to measure
red_1() {
    grep -vE 'resolv-conf: /run/systemd/resolve/resolv.conf' "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml" > "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml.tooth" \
        && mv "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml.tooth" "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml"; }
