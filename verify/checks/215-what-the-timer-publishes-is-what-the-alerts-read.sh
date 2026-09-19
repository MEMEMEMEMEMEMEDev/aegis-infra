# title: what the update timer publishes is what the alerts read, and the timer cannot act
# origin: new in v3 — 2026-09-18, a rule that reads a series nobody publishes goes empty, not red (plan/17)
check() {
# AN EMPTY RULE IS NOT A GREEN ONE, AND IT LOOKS EXACTLY LIKE ONE.
#
# The daily timer measures what is behind and pushes it to vmsingle;
# the alerts read those series and are the only thing that tells the
# operator a window is due. If a rule names a series the producer does
# not publish, it does not go red — it goes EMPTY, and an empty rule is
# indistinguishable from a platform with nothing to update. That is the
# failure this whole product is written against, wearing its most
# convincing disguise.
#
# The join is checked in BOTH directions, and the second one matters
# almost as much: a series nobody reads is dead weight that looks like
# coverage, and the doctrine that forbids a pin index forbids it too.
#
# And the third property is the operator's decision rather than an
# engineering one: THE TIMER NOTICES, IT DOES NOT ACT. A window changes
# the platform, takes the sites off the air and can roll itself back,
# and none of that happens because a clock said so. It is read off the
# unit's own command line, not off the sentence in its description.
D215=""
[[ -f "$AEGIS_ROOT/share/systemd/aegis-update-notice.service" ]] || { skip "this artifact ships no update notice timer"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/215.py" ]] || { fail "check 215 has no sidecar: the producer and the alerts were never joined"; return; }

OUT215="$(python3 "$AEGIS_ROOT/verify/checks/215.py" "$AEGIS_ROOT" 2>&1)"
RC215=$?
if (( RC215 != 0 )); then
    fail "the exercise of check 215 itself failed (rc $RC215): $OUT215"
    return
fi
SCOPE215=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE215="${hit#SCOPE: }" ;;
        *)       D215="$D215 $hit;" ;;
    esac
done <<< "$OUT215"

printf '    %s\n' "${SCOPE215:-the scope was not reported}"
if [[ -n "$D215" ]]; then
    fail "what is measured and what is watched have drifted apart:$D215"
else
    pass "every series the producer publishes is read by an alert and every alert reads one it publishes, the family has its silence sibling, and the timer runs only verbs that change nothing ($SCOPE215)"
fi
}
