# teeth for check 059 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE '_phase_rc=\$?' "$AEGIS_ROOT/libexec/aegis-init" > "$AEGIS_ROOT/libexec/aegis-init.tooth" \
        && mv "$AEGIS_ROOT/libexec/aegis-init.tooth" "$AEGIS_ROOT/libexec/aegis-init"
}
