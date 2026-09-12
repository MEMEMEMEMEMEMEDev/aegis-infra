# title: the vocabulary a form is offered is the vocabulary the validator accepts
# origin: new in v3 — 2026-09-12, `aegis org schema` is what the console's form reads (plan/15 §12)
check() {
# `aegis org schema` exists so that the console can put a form in front
# of somebody who does not write YAML. A form is a list of choices, and
# the dangerous thing about a list of choices is that it can be
# RIGHT-LOOKING and wrong: five types where the platform speaks six, a
# `puerto` field on a worker, a quota plan added to plans.yaml this
# morning that nothing offers.
#
# None of those fails loudly. The form renders; the person fills it in;
# and either the contract is rejected at the end with a message about a
# field they were invited to fill, or something the platform supports
# simply cannot be created and nothing anywhere says so.
#
# So the loop is closed behaviourally, in both directions: what the
# schema calls REQUIRED has to be enough to pass `validate`, what it
# calls FORBIDDEN has to be refused, every option it offers has to be
# accepted, and a word it does not offer has to be rejected. Two
# programs are asked the same question and their answers compared —
# nothing is imported and nothing is grepped.
D097=""
[[ -f "$LIBS/aegis/org.py" ]] || { skip "there is no generator: nothing describes a contract"; return; }
grep -q '"schema"' <<<"$(nc "$LIBS/aegis/org.py")" || { skip "aegis org has no \`schema\` verb yet: this check has no subject"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/097.py" ]] || { fail "check 097 has no sidecar: the loop cannot be closed"; return; }

OUT097="$(python3 "$AEGIS_ROOT/verify/checks/097.py" "$AEGIS_ROOT" 2>&1)"
RC097=$?
if (( RC097 != 0 )); then
    fail "the exercise of check 097 itself failed (rc $RC097) and the two vocabularies were never compared: $OUT097"
    return
fi
SCOPE097=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE097="${hit#SCOPE: }" ;;
        *)       D097="$D097 $hit;" ;;
    esac
done <<< "$OUT097"

printf '    %s\n' "${SCOPE097:-the scope was not reported}"
if [[ -n "$D097" ]]; then
    fail "the form would be offered a vocabulary the validator does not speak:$D097"
else
    pass "every choice the schema offers is accepted, every field it forbids is refused, and a word it does not offer is rejected ($SCOPE097)"
fi
}
