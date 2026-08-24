# teeth for check 093 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE '\(\(\s*said\s*\)\)\s*\|\|\s*notice' "$AEGIS_ROOT/libexec/aegis-check" > "$AEGIS_ROOT/libexec/aegis-check.tooth" \
        && mv "$AEGIS_ROOT/libexec/aegis-check.tooth" "$AEGIS_ROOT/libexec/aegis-check"
}
