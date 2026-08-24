# teeth of check 034 — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# takes out of the artifact exactly what the check claims to measure
red_1() {
    grep -vE 'force_run=true' "$AEGIS_ROOT/libexec/aegis-init" > "$AEGIS_ROOT/libexec/aegis-init.tooth" \
        && mv "$AEGIS_ROOT/libexec/aegis-init.tooth" "$AEGIS_ROOT/libexec/aegis-init"
}
