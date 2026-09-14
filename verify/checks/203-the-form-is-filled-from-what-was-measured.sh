# title: the form is filled from what was measured, and the one guess says it is one
# origin: new in v3 — 2026-09-14, importing a repository fills a form somebody will accept without reading (plan/15 §16)
check() {
# IMPORTING A REPOSITORY FILLS A FORM FOR SOMEBODY, and every value it
# puts there is one that person is likely to accept without reading —
# which is the whole point of filling it, and why a form that invents is
# worse than a form that is blank. A blank asks.
#
# MEASURED WHILE WRITING IT. The first version built the repository's
# URL as `git@github.com:owner/<name>.git`, with the word `owner` in it,
# because the owner was not to hand. That contract VALIDATES. It points
# at a repository that is not yours, the deploy key goes to the wrong
# place, and the first push builds nothing — from a field somebody was
# shown already filled and had no reason to doubt.
#
# So every field is either DERIVED from the reading or left empty, with
# exactly one exception: the type is suggested from the language,
# because making somebody choose between six words when five are
# obviously wrong is ceremony rather than honesty. The suggestion falls
# towards `http`, which is the type that refuses least — a static front
# declared http starts and serves, while an http service declared static
# has nowhere to run — and the form says out loud that it guessed.
D203=""
[[ -f "$LIBS/aegis/console.py" ]] || { skip "there is no renderer: this check has no subject"; return; }
grep -q 'def import_fields' <<<"$(nc "$LIBS/aegis/console.py")" || { skip "the console does not import a repository yet: this check has no subject"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/203.py" ]] || { fail "check 203 has no sidecar: the form was never filled"; return; }

OUT203="$(python3 "$AEGIS_ROOT/verify/checks/203.py" "$AEGIS_ROOT" 2>&1)"
RC203=$?
if (( RC203 != 0 )); then
    fail "the exercise of check 203 itself failed (rc $RC203) and no form was filled: $OUT203"
    return
fi
SCOPE203=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE203="${hit#SCOPE: }" ;;
        *)       D203="$D203 $hit;" ;;
    esac
done <<< "$OUT203"

printf '    %s\n' "${SCOPE203:-the scope was not reported}"
if [[ -n "$D203" ]]; then
    fail "the form arrives carrying something nobody measured:$D203"
else
    pass "every field comes from the reading or is left blank, the one suggestion falls towards the type that refuses least, and the form says it guessed ($SCOPE203)"
fi
}
