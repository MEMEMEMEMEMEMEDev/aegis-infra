# teeth for check 081 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'STATE_SECRETS' "$AEGIS_ROOT/libexec/aegis-rotate" > "$AEGIS_ROOT/libexec/aegis-rotate.tooth" \
        && mv "$AEGIS_ROOT/libexec/aegis-rotate.tooth" "$AEGIS_ROOT/libexec/aegis-rotate"
}
