# title: a step's payload cannot collide with a keyword named beside it
# origin: new in v3 — 2026-09-20, a window died of TypeError with the maintenance page up
check() {
# IT RAISED IN THE MIDDLE OF A REAL WINDOW.
#
#     steps.wrong("window:maintenance-no-effect", **seen,
#                 por_que="the hook ran and the public sites still answer…")
#
# `seen` had just learned to carry its own `por_que`, so Python raised
# «got multiple values for keyword argument» and the window died with
# the page up and the sites off the air. The exit trap brought
# everything back, which is the only reason this reads as a bug and not
# as an incident — but where a verdict should have been there were a
# hundred lines of traceback, and nothing had ever warned.
#
# THE SHAPE OF THE TRAP: `f(**payload, key=value)` is correct right up
# until something adds `key` to the payload, and the two are written
# months apart by somebody thinking about something else. This tree
# carried twenty-seven of them across five commands; two were already
# live.
#
# THE RULE is blunt on purpose: a call that emits a step or writes a
# journal entry may splat a dictionary, or name keywords, and not both.
# `**{**payload, "key": value}` says the same thing, cannot raise, and
# says out loud which one wins.
D219=""
[[ -f "$AEGIS_ROOT/verify/checks/219.py" ]] || { fail "check 219 has no sidecar: no call was read"; return; }

OUT219="$(python3 "$AEGIS_ROOT/verify/checks/219.py" "$AEGIS_ROOT" 2>&1)"
RC219=$?
if (( RC219 != 0 )); then
    fail "the exercise of check 219 itself failed (rc $RC219): $OUT219"
    return
fi
SCOPE219=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE219="${hit#SCOPE: }" ;;
        *)       D219="$D219 $hit;" ;;
    esac
done <<< "$OUT219"

printf '    %s\n' "${SCOPE219:-the scope was not reported}"
if [[ -n "$D219" ]]; then
    fail "a verdict can turn into a TypeError the day a payload grows a key:$D219"
else
    pass "no step-emitting call can collide with its own payload ($SCOPE219)"
fi
}
