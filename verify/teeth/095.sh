# teeth for check 095 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'cd "\$RAIZ/tofu" && "\$WRAPPER"' "$AEGIS_ROOT/libexec/aegis-vps" > "$AEGIS_ROOT/libexec/aegis-vps.tooth" \
        && mv "$AEGIS_ROOT/libexec/aegis-vps.tooth" "$AEGIS_ROOT/libexec/aegis-vps"
}
