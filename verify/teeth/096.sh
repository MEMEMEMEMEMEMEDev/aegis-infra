# teeth for check 096 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'AEGIS_STATE_DIR' "$AEGIS_ROOT/libexec/aegis-init-log" > "$AEGIS_ROOT/libexec/aegis-init-log.tooth" \
        && mv "$AEGIS_ROOT/libexec/aegis-init-log.tooth" "$AEGIS_ROOT/libexec/aegis-init-log"
}
