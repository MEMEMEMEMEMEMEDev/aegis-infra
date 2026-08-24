# teeth of check 042 — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# takes out of the artifact exactly what the check claims to measure
red_1() {
    grep -vE 'skipped due to when conditional' "$AEGIS_ROOT/init/phases/70-deploy-auto.sh" > "$AEGIS_ROOT/init/phases/70-deploy-auto.sh.tooth" \
        && mv "$AEGIS_ROOT/init/phases/70-deploy-auto.sh.tooth" "$AEGIS_ROOT/init/phases/70-deploy-auto.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/70-deploy-auto.sh"; }
