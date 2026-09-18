# title: every class of pin is owned by a layer, and every layer is judged by sections the round has
# origin: new in v3 — 2026-09-18, an acceptance that reads an empty set is green whatever happens (plan/17)
check() {
# THE FAILURE THIS FORBIDS IS A GREEN THAT MEANS NOTHING.
#
# The classes of pin are derived from the tree. The layers are written
# down, because they are a property of the protocol and nothing in the
# platform says that charts come after k3s. Written down is fine;
# written down and then quietly out of step with the other is not.
#
# A class nobody gave a layer is a class a window walks straight past:
# reported as behind by the inventory, proposed by the plan, and never
# touched, month after month, while the window says «accepted».
#
# And a layer judged by a section the round no longer has is worse,
# because it does not go red — its acceptance compares an empty set and
# passes always. That is the shape this whole product is written
# against: not a wrong answer, an answer nobody measured.
D213=""
[[ -f "$AEGIS_ROOT/lib/aegis/window.py" ]] || { skip "there are no layers yet"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/213.py" ]] || { fail "check 213 has no sidecar: the layers and the classes were never joined"; return; }

OUT213="$(python3 "$AEGIS_ROOT/verify/checks/213.py" "$AEGIS_ROOT" 2>&1)"
RC213=$?
if (( RC213 != 0 )); then
    fail "the exercise of check 213 itself failed (rc $RC213): $OUT213"
    return
fi
SCOPE213=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE213="${hit#SCOPE: }" ;;
        *)       D213="$D213 $hit;" ;;
    esac
done <<< "$OUT213"

printf '    %s\n' "${SCOPE213:-the scope was not reported}"
if [[ -n "$D213" ]]; then
    fail "the layers and what they change have drifted apart:$D213"
else
    pass "every class of pin has exactly one layer that applies it, every layer says how it is undone and what it costs, and every section it is judged by exists in the round ($SCOPE213)"
fi
}
