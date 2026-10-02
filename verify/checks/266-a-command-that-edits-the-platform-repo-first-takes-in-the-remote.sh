# title: a command that edits the platform repo first takes in what the remote has (fast-forward only)
# origin: new in v3 — 2026-10-02, plan/21 stage 6: image-watch starts committing the ledger and the exploited list to the platform repo every morning; `aegis image request` and `aegis update` pushed from a clone nobody brought up to date
check() {
# The platform repo has writers on both sides: the operator's commands on
# this machine and, in the cluster, image-watch (every morning) and
# base-images. The sidecar RUNS update's catch-up between two real repos
# and reads aegis-image's list loader.
D266=""
[[ -f "$AEGIS_ROOT/verify/checks/266.py" ]] || { fail "check 266 has no sidecar"; return; }
OUT266="$(python3 "$AEGIS_ROOT/verify/checks/266.py" "$AEGIS_ROOT" 2>&1)"
RC266=$?
(( RC266 == 0 )) || { fail "the exercise of check 266 itself failed (rc $RC266): ${OUT266:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE266="${hit#SCOPE: }" ;;
        *)       D266="$D266 $hit;" ;;
    esac
done <<< "$OUT266"
printf '    %s\n' "${SCOPE266:-the scope was not reported}"
if [[ -n "$D266" ]]; then
    fail "a command edits the platform repo on a clone the remote has moved past:$D266"
else
    pass "update's refusals take in the remote before the first edit and refuse when they cannot; image request/gc sync before a real run (${SCOPE266})"
fi
}
