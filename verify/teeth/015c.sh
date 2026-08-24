# teeth of check 015c — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# the subject disappears: if the check does not notice, it was not
# reading it
red_1() { rm -f "$AEGIS_ROOT/lib/cf-policy-access.py"; }

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/lib/cf-policy-access.py"; }
