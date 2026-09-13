# title: an edit changes what you changed, and nothing else
# origin: new in v3 — measured on 2026-09-13 opening the edit screen over a real contract (plan/15 §14)
check() {
# MEASURED, NOT IMAGINED. The form shows six fields per service. A
# contract carries more: `usa`, the `almacenamiento` block, the whole
# `ai` section with its list of tasks. The first version of this screen
# REBUILT the contract from the form, and every one of those
# disappeared.
#
# Nothing refused it. `usa` is optional, so the validator had nothing to
# say; the plan showed a tidy diff of the files it would rewrite; the
# page said it saved. Somebody adding a database to their shop would
# have silently deleted the four capabilities its API declares, and
# found out when the NetworkPolicies stopped letting it reach any of
# them.
#
# The shape that fixes it is «the current contract is the floor». The
# shape that PROVES it is this check: it edits a contract carrying
# everything the screen does not show, and demands that the only
# difference is the thing that was asked for.
#
# And the three refusals, because an edit that may do anything is not an
# edit: it may not drop a service (a database takes its volume with it),
# it may not rename the organization (that writes a second contract and
# leaves the first), and it may not create one. Plus the honest half —
# a legitimate change has to go through, or a function that refused
# everything would satisfy every line above.
D201=""
[[ -f "$LIBS/aegis/console.py" ]] || { skip "there is no renderer: this check has no subject"; return; }
grep -q 'def contract_from_edit' <<<"$(nc "$LIBS/aegis/console.py")" || { skip "the console does not edit yet: this check has no subject"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/201.py" ]] || { fail "check 201 has no sidecar: the edit was never exercised"; return; }

OUT201="$(python3 "$AEGIS_ROOT/verify/checks/201.py" "$AEGIS_ROOT" 2>&1)"
RC201=$?
if (( RC201 != 0 )); then
    fail "the exercise of check 201 itself failed (rc $RC201) and no edit was tried: $OUT201"
    return
fi
SCOPE201=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE201="${hit#SCOPE: }" ;;
        *)       D201="$D201 $hit;" ;;
    esac
done <<< "$OUT201"

printf '    %s\n' "${SCOPE201:-the scope was not reported}"
if [[ -n "$D201" ]]; then
    fail "an edit does more than what was edited:$D201"
else
    pass "the edit changes only what the form shows, keeps everything it does not, refuses to drop a service, to rename and to create, and the two write doors stay distinct ($SCOPE201)"
fi
}
