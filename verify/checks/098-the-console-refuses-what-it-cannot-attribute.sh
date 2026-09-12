# title: the console refuses a request it cannot attribute, and a write it cannot attribute twice
# origin: new in v3 — 2026-09-12, before the console writes anything (plan/15 §12, E3)
check() {
# TWO ATTACKS REACH A SERVER ON 127.0.0.1 FROM THE INTERNET, and neither
# looks like one from inside the process: the request is well-formed, it
# arrives over loopback, and the operator is sitting in front of the
# browser that sent it.
#
#   DNS REBINDING gets the read-only console. A page keeps its own
#   origin while its name starts resolving to 127.0.0.1 — same-origin
#   policy is not violated, it simply does not apply. The only thing
#   that gives it away is the Host header, and until 2026-09-12 this
#   console answered to any.
#
#   CSRF gets the write. Cross-origin form POSTs have never been blocked
#   by same-origin policy. The defence is a token the attacking page
#   cannot READ: it can send a request and it cannot see the answer.
#
# The rules live in lib/aegis/guard.py as a pure function so that they
# can be EXERCISED instead of reviewed, and this runs them over a table
# of hostile requests. The second half is not optional: a guard that
# refused everything would satisfy every hostile row and serve nobody,
# so the legitimate request has to get through. And then the server's
# own source is read, because a module that is right and unused is the
# most reassuring kind of wrong.
D098=""
[[ -f "$LIBS/aegis/guard.py" ]] || { skip "there is no guard: the console has no rules to exercise"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/098.py" ]] || { fail "check 098 has no sidecar: the rules were never exercised"; return; }

OUT098="$(python3 "$AEGIS_ROOT/verify/checks/098.py" "$AEGIS_ROOT" 2>&1)"
RC098=$?
if (( RC098 != 0 )); then
    fail "the exercise of check 098 itself failed (rc $RC098) and no rule was tried: $OUT098"
    return
fi
SCOPE098=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE098="${hit#SCOPE: }" ;;
        *)       D098="$D098 $hit;" ;;
    esac
done <<< "$OUT098"

printf '    %s\n' "${SCOPE098:-the scope was not reported}"
if [[ -n "$D098" ]]; then
    fail "a page on the internet can reach this console through the operator's browser:$D098"
else
    pass "every request the console cannot attribute is refused, its own page is not, and every handler asks ($SCOPE098)"
fi
}
