# teeth of check 015d — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# takes out of the artifact exactly what the check claims to measure
red_1() {
    grep -vE 'gen_or_restore' "$AEGIS_ROOT/lib/secrets.sh" > "$AEGIS_ROOT/lib/secrets.sh.tooth" \
        && mv "$AEGIS_ROOT/lib/secrets.sh.tooth" "$AEGIS_ROOT/lib/secrets.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/lib/secrets.sh"; }
