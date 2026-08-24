# teeth of check 047 — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# takes out of the artifact exactly what the check claims to measure
red_1() {
    grep -vE 'operationState.message' "$AEGIS_ROOT/lib/common.sh" > "$AEGIS_ROOT/lib/common.sh.tooth" \
        && mv "$AEGIS_ROOT/lib/common.sh.tooth" "$AEGIS_ROOT/lib/common.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/lib/common.sh"; }
