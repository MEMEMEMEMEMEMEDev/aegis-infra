# teeth for check 057 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'status_code' "$AEGIS_ROOT/init/phases/60-webhook.sh" > "$AEGIS_ROOT/init/phases/60-webhook.sh.tooth" \
        && mv "$AEGIS_ROOT/init/phases/60-webhook.sh.tooth" "$AEGIS_ROOT/init/phases/60-webhook.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/60-webhook.sh"; }
