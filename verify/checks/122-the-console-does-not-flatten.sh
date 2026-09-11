# title: the console does not flatten — no state is lost between the document and the screen
# origin: new in v3 — 2026-09-11, the invariant the whole corpus exists to make checkable (plan/15 §4)
check() {
# THIS IS THE ONE. Everything else in this family is scaffolding for it.
#
# aegis has four outcomes and the third one is the reason the product
# exists: «I could not look» is NOT «it is fine». The CLI defends that
# with 190-odd checks. The screen is where it gets lost, because
# flattening four states into two colours is what every dashboard on
# the market does — and it does it silently, in a template, in a line
# nobody reviews.
#
# So the two invariants are asserted by RENDERING every case of the
# corpus and reading the result back:
#
#   I-1  no state is lost and none is invented. Every distinct state the
#        documents carry reaches the screen; every state on the screen
#        comes from the documents.
#   I-2  the verdict cannot be kinder than the readings. If something
#        could not be evaluated — or gave back no document at all — the
#        page may not end up saying everything is fine.
#
# BOTH ARE ASSERTED ON ATTRIBUTES, never on words. That is not a detail:
# the product's interface is in English, the sketches were in Spanish,
# and neither ties this check. `data-state` is the contract.
#
# And one static rule holds the other two up: the map from the words the
# producers speak to the ones the screen shows must be TOTAL — a word
# with no translation is a state the screen cannot show — and it may
# never send a word that means «could not look» to one the screen counts
# as looked at. WHICH words those are is read from lib/aegis/outcomes.py
# and from the round's own translation line, never decided here: a check
# that carried its own list of what rc 2 means would be one more place
# for the contract to drift.
D122=""
[[ -f "$LIBS/aegis/console.py" ]] || { skip "there is no renderer yet ($LIBS/aegis/console.py): the console cannot flatten what it does not draw"; return; }

OUT122="$(python3 "$AEGIS_ROOT/verify/checks/122.py" "$AEGIS_ROOT" 2>&1)"
RC122=$?
if (( RC122 != 0 )); then
    fail "the renderer of check 122 itself failed (rc $RC122) and nothing was asserted about flattening: $OUT122"
    return
fi
SCOPE122=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE122="${hit#SCOPE: }" ;;
        *)       D122="$D122 $hit;" ;;
    esac
done <<< "$OUT122"

printf '    %s\n' "${SCOPE122:-the scope was not reported}"
if [[ -n "$D122" ]]; then
    fail "the console flattens what the CLI measured:$D122"
else
    pass "every state of every case reaches the screen, none is invented, and no verdict is kinder than its readings ($SCOPE122)"
fi
}
