# teeth for check 051 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# the subject disappears: if the check does not notice, it was not reading it
red_1() { rm -f "$AEGIS_ROOT/init/phases/80-supply-chain.sh"; }

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/80-supply-chain.sh"; }
