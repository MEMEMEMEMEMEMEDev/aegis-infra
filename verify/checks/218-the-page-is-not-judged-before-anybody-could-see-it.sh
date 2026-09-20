# title: the maintenance page is not judged before the probes could have seen it
# origin: new in v3 — 2026-09-20, the first real window stopped saying the page did nothing, and the page was up
check() {
# IT STOPPED FOR A REASON THAT WAS NOT TRUE.
#
# The first update window ever opened on a real instance deployed the
# maintenance page in 5.5 seconds, read the round at once, and answered
# «the hook ran and the public sites still answer». The page was up.
# The tenant probes run every thirty seconds and had not run again yet,
# so the round was describing a world that no longer existed.
#
# Stopping was right — the window will not act on a measurement it
# cannot trust. Printing a false reason was not, and a protocol that
# halts for false reasons is one nobody lets run unattended.
#
# So the reading waits, the wait comes from how often the probes
# ACTUALLY run —read from the platform's own config, not typed here—
# and everything below is driven in milliseconds with an injected clock
# and an injected reader, so no cluster is touched to prove it.
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
    fail "the window can judge the page before anybody could have seen it:$D218"
else
    pass "the reading waits a probe interval before asking, asks again, derives that interval from the platform's own config, and says so when it is guessing ($SCOPE218)"
fi
}
