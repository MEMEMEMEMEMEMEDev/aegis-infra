# teeth of check 050 — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# takes out of the artifact exactly what the check claims to measure
red_1() {
    grep -vE 'grep -q .require-aegis-signature. <<<' "$AEGIS_ROOT/init/phases/80-supply-chain.sh" > "$AEGIS_ROOT/init/phases/80-supply-chain.sh.tooth" \
        && mv "$AEGIS_ROOT/init/phases/80-supply-chain.sh.tooth" "$AEGIS_ROOT/init/phases/80-supply-chain.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/80-supply-chain.sh"; }
