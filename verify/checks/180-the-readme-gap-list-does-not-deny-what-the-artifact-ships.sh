# title: the README's list of gaps does not deny what the artifact already ships
# origin: new in v3 — 2026-09-02, four claims found false while reviewing the seed before an install from zero
check() {
# MEASURED 2026-09-02. The README's «Lo que no está» said four things
# that had stopped being true:
#
#   · one application template, when the seed ships six;
#   · `aegis data restore` leaves the bucket's objects behind, when it
#     puts them back;
#   · after `--force` the database role is realigned by hand, when the
#     command issues the ALTER ROLE itself;
#   · `aegis secret create` does not derive the registry credential's
#     per-namespace copy, when it does.
#
# None of them is a typo. Each was TRUE when written, and the artifact
# outgrew the sentence while nobody looked, because the section that
# lists what a product cannot do is the section nobody revisits when a
# product learns something.
#
# It is not cosmetic. A gap list is read as instructions: an operator
# who believes restore leaves the objects behind re-uploads a catalogue
# by hand, and one who believes the role needs realigning types an
# ALTER ROLE into a database that did not need it. Understating a
# product costs the reader work, and it costs it at the worst moment,
# which is while they are restoring.
#
# It is the same decay check 179 hunts in runtime messages, one floor
# up: there the product tells the operator a verb does not exist, here
# it tells them a capability does not exist. Both are claims of absence,
# and a claim of absence is never typed by anybody, so it never fails
# loudly the way a wrong command name does.
#
# WHAT THIS DOES NOT MEASURE, said plainly because the honest shape of
# this check is narrow: a gap claim added tomorrow is not covered until
# somebody derives its fact from the tree. It guards the four that
# actually decayed and the class they belong to, and every answer comes
# from the code, never from a list of truths kept inside the check.
D180=""
[[ -f "$AEGIS_ROOT/README.md" ]] || { skip "there is no README.md: this check has no subject"; return; }

OUT="$(python3 "$AEGIS_ROOT/verify/checks/180.py" "$AEGIS_ROOT" 2>/dev/null)"
RC=$?
if (( RC != 0 )); then
    fail "the scan of check 180 itself failed (rc $RC) and this check measured nothing about the README"
    return
fi
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    D180="$D180 $hit;"
done <<< "$OUT"

read -r NC NP < <(python3 "$AEGIS_ROOT/verify/checks/180.py" "$AEGIS_ROOT" 2>&1 >/dev/null | awk '/__COUNT__/{print $2, $3}')
printf '    %s claims answered against the tree · %s templates shipped by the seed\n' "${NC:-0}" "${NP:-0}"
if [[ -n "$D180" ]]; then fail "the README denies something the product already does:$D180"
else pass "every gap the README declares is still a gap, measured against the tree and not against a list kept here"; fi
}
