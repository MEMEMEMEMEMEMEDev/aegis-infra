# title: a capacity nobody could measure is never reported as zero, and the plans are read from plans.yaml
# origin: new in v3 — 2026-09-12, `aegis capacity` answers «does another organization fit?» (plan/11 §B4)
check() {
# THE QUESTION THIS COMMAND ANSWERS is the one an operator asks under
# pressure — «does another one fit?» — and the answer arrives as a
# number. That is exactly the shape where the third outcome dies
# quietly: on a screen, «no room» and «I could not look» are the same
# sentence, and they are opposite facts. One says stop. The other says
# go and find out.
#
# So the first half of this check is behavioural: it runs the real
# command against a dead kubeconfig and demands rc 2, a step filed as
# `not-evaluable`, and —above all— that no plan comes back with room 0.
# A zero there would refuse an organization that fits, on a machine
# nobody ever asked.
#
# The second half is the house rule about numbers: they live in
# plans.yaml, they are readjusted for every organization at once, and a
# copy of them inside this command would keep answering confidently
# after they move. The plan NAMES are derived from plans.yaml and looked
# for in the source — if the command mentions one, it is deciding
# something about it.
#
# Nothing is created and no cluster is contacted: kubectl with
# KUBECONFIG=/dev/null finds nothing and says so, which is the whole
# point.
D131=""
[[ -f "$LIBEXEC/aegis-capacity" ]] || { skip "there is no capacity command yet: nothing answers whether another organization fits"; return; }

OUT131="$(python3 "$AEGIS_ROOT/verify/checks/131.py" "$AEGIS_ROOT" 2>&1)"
RC131=$?
if (( RC131 != 0 )); then
    fail "the exercise of check 131 itself failed (rc $RC131) and blindness was never measured: $OUT131"
    return
fi
SCOPE131=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE131="${hit#SCOPE: }" ;;
        *)       D131="$D131 $hit;" ;;
    esac
done <<< "$OUT131"

printf '    %s\n' "${SCOPE131:-the scope was not reported}"
if [[ -n "$D131" ]]; then
    fail "the capacity answer confuses «full» with «unmeasured», or carries its own numbers:$D131"
else
    pass "with no cluster the command says it could not look instead of answering zero, and what each plan costs comes from plans.yaml ($SCOPE131)"
fi
}
