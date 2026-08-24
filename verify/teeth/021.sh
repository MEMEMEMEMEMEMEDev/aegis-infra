# teeth of check 021 — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# takes out of the artifact exactly what the check claims to measure
red_1() {
    grep -vE 'rm -f .*\$TUNNEL_ENV/terraform\.tfstate' "$AEGIS_ROOT/init/phases/25-edge-tofu.sh" > "$AEGIS_ROOT/init/phases/25-edge-tofu.sh.tooth" \
        && mv "$AEGIS_ROOT/init/phases/25-edge-tofu.sh.tooth" "$AEGIS_ROOT/init/phases/25-edge-tofu.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/25-edge-tofu.sh"; }
