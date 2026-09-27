# title: under pipefail, nothing pipes a producer into `grep -q` — the match reads a process substitution
# origin: new in v3 — 2026-09-24, lab-arch and lab-debian13 (the experimental's H-05): the retry read «NO network signature» with TOOMANYREQUESTS in the console, half of the time
check() {
# `grep -q` quits at the first match; a producer still writing dies of
# SIGPIPE and pipefail turns the match into «no». jenkins_build_retry
# lost network signatures that way and cut builds it should have retried.
# The sidecar blanks comments, quoted strings (a `bash -c` string runs
# without pipefail) and heredocs, and looks for the pipe in what is left.
D253=""
[[ -f "$AEGIS_ROOT/verify/checks/253.py" ]] || { fail "check 253 has no sidecar"; return; }
OUT253="$(python3 "$AEGIS_ROOT/verify/checks/253.py" "$AEGIS_ROOT" 2>&1)"
RC253=$?
(( RC253 == 0 )) || { fail "the scan of check 253 itself failed (rc $RC253): ${OUT253:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE253="${hit#SCOPE: }" ;;
        *)       D253="$D253 $hit;" ;;
    esac
done <<< "$OUT253"
printf '    %s\n' "${SCOPE253:-the scope was not reported}"
if [[ -n "$D253" ]]; then
    fail "a match under pipefail can read «no» because the producer died of SIGPIPE — use grep -q … < <(producer):$D253"
else
    pass "no producer is piped into grep -q under pipefail; every match reads the whole output (${SCOPE253})"
fi
}
