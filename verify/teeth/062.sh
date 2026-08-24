# teeth for check 062 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'AEGIS_AGE_BACKUP_FILE' "$AEGIS_ROOT/lib/secrets.sh" > "$AEGIS_ROOT/lib/secrets.sh.tooth" \
        && mv "$AEGIS_ROOT/lib/secrets.sh.tooth" "$AEGIS_ROOT/lib/secrets.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/lib/secrets.sh"; }
