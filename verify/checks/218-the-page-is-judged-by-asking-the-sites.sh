# title: the maintenance page is judged by asking the sites, not by reading the round
# origin: new in v3 — 2026-09-20, four windows in a row said the page did nothing while it was up
check() {
# FOUR WINDOWS IN A ROW SAID THE PAGE HAD DONE NOTHING, and it was up.
#
# Each version was wrong differently, and every one looked reasonable:
# it read the round the instant the hook returned, when the tenant
# probes run every thirty seconds; it counted only a reading that went
# from fine to not fine, and ignored the one that DISAPPEARED; it
# watched only readings that had been GREEN, and this instance's line
# about its sites was already a notice; and finally, with all of that
# fixed, the round's keys flatten digits —that is what makes two rounds
# comparable— so «1 of the 5 public site(s) do not answer» and «5 of
# the 5» are one key with one state, and the page's whole effect is
# that number.
#
# The round is the wrong instrument: it measures the ORIGIN, through
# probes, with a minute of lag, and the page lives at the EDGE. So the
# window asks the public URLs itself and compares against the codes it
# took as part of its photo. What it demands is only that SOMETHING
# CHANGED — aegis knows nothing about what the operator's page returns,
# and two of these sites answer 302 on an ordinary day.
#
# All of it driven with an injected clock and an injected lookup: no
# network, no cluster, milliseconds.
D218=""
[[ -f "$AEGIS_ROOT/lib/aegis/window.py" ]] || { skip "there is no window machinery yet"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/218.py" ]] || { fail "check 218 has no sidecar: the reading was never driven"; return; }

OUT218="$(python3 "$AEGIS_ROOT/verify/checks/218.py" "$AEGIS_ROOT" 2>&1)"
RC218=$?
if (( RC218 != 0 )); then
    fail "the exercise of check 218 itself failed (rc $RC218): $OUT218"
    return
fi
SCOPE218=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE218="${hit#SCOPE: }" ;;
        *)       D218="$D218 $hit;" ;;
    esac
done <<< "$OUT218"

printf '    %s\n' "${SCOPE218:-the scope was not reported}"
if [[ -n "$D218" ]]; then
    fail "the window can be wrong about whether its own page did anything:$D218"
else
    pass "the page is judged by asking the public sites, after waiting and more than once, against the codes the photo took, and an instance with no site says so instead of saying the page did nothing ($SCOPE218)"
fi
}
