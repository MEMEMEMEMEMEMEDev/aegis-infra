# teeth for check 054 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'gates.jsonl' "$AEGIS_ROOT/lib/common.sh" > "$AEGIS_ROOT/lib/common.sh.tooth" \
        && mv "$AEGIS_ROOT/lib/common.sh.tooth" "$AEGIS_ROOT/lib/common.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/lib/common.sh"; }
