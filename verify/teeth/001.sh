# teeth of check 001 (bash -n of every script)
#
# Deleting a file is no good as a tooth here: the check would count one
# less and stay green. The only thing that proves this check MEASURES
# is feeding broken syntax to a real script.

# an `if` with no `fi` — the most common mistake when editing a phase
# at 2 AM
red_1() {
    printf '\nif [[ -f /tmp/x ]]; then\n    echo hello\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"
}

# an unclosed quote in a lib: bash -n sees it, a grep does not
red_2() {
    printf '\necho "this does not close\n' >> "$AEGIS_ROOT/lib/jenkins.sh"
}

# and in a command, not only in the phases: the scope of v3 includes
# libexec/ and lib/, which in v2 lived somewhere else
red_3() {
    printf '\ncase x in\n' >> "$AEGIS_ROOT/libexec/aegis-rotate"
}

# control: a new comment is not a syntax error
control_1() { printf '\n# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }

# a library module —with no shebang, because it is not a command— with
# broken syntax. Until 2026-08-24 this tooth would NOT have bitten: the
# language came only from the shebang, and the six modules of lib/aegis/
# were checked by accident, depending on whether their docstring
# mentioned the word «python». 5,800 lines covered by chance.
red_4() {
    printf '\ndef broken(:\n' >> "$AEGIS_ROOT/lib/aegis/markers.py"
}
