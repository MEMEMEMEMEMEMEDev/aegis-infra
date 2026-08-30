# teeth of check 157 — the wizard offers no answer the artifact cannot
# honour. Every red below was applied over a copy of the tree and the
# check went red.

# THE FOUNDING REGRESSION, run backwards: take phase 87 away and `gpu`
# and `cpu` go back to being answers nobody serves. This is the state
# the artifact was actually in until 2026-08-29, and the check has to
# be able to see it — otherwise it was written to fit today's tree.
red_1() { rm -f "$AEGIS_ROOT/init/phases/87-ai.sh" "$AEGIS_ROOT/libexec/aegis-ai" \
                "$AEGIS_ROOT/libexec/aegis-sync" "$AEGIS_ROOT/libexec/aegis-check"; }

# a value ADDED to the validator and served by nobody: the same defect
# arriving by the other door, which is the one a new question opens.
red_2() {
    sed -i 's/_v_ai()      { \[\[ "$1" == no || "$1" == cpu || "$1" == gpu \]\]; }/_v_ai()      { [[ "$1" == no || "$1" == cpu || "$1" == gpu || "$1" == tpu ]]; }/' \
        "$AEGIS_ROOT/lib/config.sh"
}

# a default the wizard's own validator rejects: pressing Enter would be
# refused by the question that offered it.
red_3() { sed -i 's/ask AI "no" _v_ai/ask AI "none" _v_ai/' "$AEGIS_ROOT/lib/config.sh"; }

# the same, on the other question, so the check is not reading one
# variable by name.
red_4() { sed -i 's/ask EDGE "cloudflare" _v_edge/ask EDGE "cloudfare" _v_edge/' "$AEGIS_ROOT/lib/config.sh"; }

# and the check's own subject taken away: with no ask() bound to an
# enumerating validator, finding nothing must NOT be reported as
# nothing wrong. This is the shape of the bug found in check 004 on
# 2026-08-29.
red_5() { sed -i 's/^    ask AI /    #ask AI /; s/^    ask EDGE /    #ask EDGE /' "$AEGIS_ROOT/lib/config.sh"; }

# control: another value, served, cannot turn it red.
control_1() {
    sed -i 's/_v_ai()      { \[\[ "$1" == no || "$1" == cpu || "$1" == gpu \]\]; }/_v_ai()      { [[ "$1" == no || "$1" == cpu || "$1" == gpu || "$1" == local ]]; }/' \
        "$AEGIS_ROOT/lib/config.sh"
}

# control: prose about a value that is served changes nothing.
control_2() { printf '\n# note: gpu needs the container toolkit.\n' >> "$AEGIS_ROOT/lib/config.sh"; }
