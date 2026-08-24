# teeth of check 003b (the template guard recognizes what it looks for)
#
# The defect this check prevents: the guard of `aegis app` lets an
# unfilled placeholder through and the operator receives the repo of
# their app with __ROOT_DOMAIN__ written inside, as a literal.

# the exact pattern the product carried until 2026-08-24: it
# recognizes no placeholder with an underscore inside.
red_1() {
    sed -i 's|^PLACEHOLDER = re.compile(r"__\[A-Z0-9_\]+__")|PLACEHOLDER = re.compile(r"__[A-Z]+__")|' \
        "$AEGIS_ROOT/libexec/aegis-app"
}

# a pattern demanding lowercase: it recognizes NOTHING the seed uses.
# If the check only glanced at the pattern, this one would pass.
red_2() {
    sed -i 's|^PLACEHOLDER = re.compile(r"__\[A-Z0-9_\]+__")|PLACEHOLDER = re.compile(r"__[a-z]+__")|' \
        "$AEGIS_ROOT/libexec/aegis-app"
}

# control: an equivalent rewrite of the pattern (same language, another
# order within the class) cannot turn it red — if it does, the check is
# comparing text instead of exercising the guard.
control_1() {
    sed -i 's|^PLACEHOLDER = re.compile(r"__\[A-Z0-9_\]+__")|PLACEHOLDER = re.compile(r"__[_0-9A-Z]+__")|' \
        "$AEGIS_ROOT/libexec/aegis-app"
}
