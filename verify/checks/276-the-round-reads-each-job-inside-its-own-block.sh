# title: the round reads each multibranch job inside its own block: an empty repo is a lane switched off, never the next job's
# origin: new in v3 — 2026-10-02, alpha-debian: with AI=no the round judged ai-gateway-mb against the portfolio's repo and never looked at the portfolio's job
check() {
D276=""
[[ -f "$AEGIS_ROOT/verify/checks/276.py" ]] || { fail "check 276 has no sidecar"; return; }
OUT276="$(python3 "$AEGIS_ROOT/verify/checks/276.py" "$AEGIS_ROOT" 2>&1)"
RC276=$?
(( RC276 == 0 )) || { fail "the exercise of check 276 itself failed (rc $RC276): ${OUT276:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE276="${hit#SCOPE: }" ;;
        *)       D276="$D276 $hit;" ;;
    esac
done <<< "$OUT276"
printf '    %s\n' "${SCOPE276:-the scope was not reported}"
if [[ -n "$D276" ]]; then
    fail "the round misreads its jobs:$D276"
else
    pass "each job is read in its own block, a job with no repo is said and skipped, and the next job is judged against its own repo (${SCOPE276})"
fi
}
