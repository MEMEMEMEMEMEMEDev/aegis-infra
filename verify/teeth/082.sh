# teeth for check 082 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE '"\$TOFU".*destroy' "$AEGIS_ROOT/libexec/aegis-destroy" > "$AEGIS_ROOT/libexec/aegis-destroy.tooth" \
        && mv "$AEGIS_ROOT/libexec/aegis-destroy.tooth" "$AEGIS_ROOT/libexec/aegis-destroy"
}
