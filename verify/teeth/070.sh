# teeth for check 070 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'clusterip-coincide-con-el-service' "$AEGIS_ROOT/init/phases/40-registry-pki.sh" > "$AEGIS_ROOT/init/phases/40-registry-pki.sh.tooth" \
        && mv "$AEGIS_ROOT/init/phases/40-registry-pki.sh.tooth" "$AEGIS_ROOT/init/phases/40-registry-pki.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/40-registry-pki.sh"; }
