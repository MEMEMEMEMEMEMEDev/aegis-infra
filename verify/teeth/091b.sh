# teeth for check 091b (the hand-written copies vs the generator)
#
# This check sits at NOT EVALUABLE on purpose: the correct reference is
# the generator, and until lib/aegis/derivar.py exists there is nothing
# to compare against. The tooth proves the promise has an expiry date:
# the day the module appears, the check turns red until somebody wires
# it up. A debt that collects itself.
red_1() {
    mkdir -p "$AEGIS_ROOT/lib/aegis"
    printf 'def render_ruteo(*a, **k):\n    raise NotImplementedError\n' \
        > "$AEGIS_ROOT/lib/aegis/derivar.py"
}
