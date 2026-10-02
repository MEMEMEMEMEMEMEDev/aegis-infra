# title: the console draws the books of known vulnerabilities on Security and as a chip on each project, without inventing a state
# origin: new in v3 — 2026-10-02, plan/21 stage 7: the books existed (aegis vulns) and the console, where the operator looks, did not show them
check() {
# The sidecar RENDERS console/cases/security-vulns and reads the result
# by attribute, never by word.
D270=""
[[ -f "$AEGIS_ROOT/verify/checks/270.py" ]] || { fail "check 270 has no sidecar"; return; }
OUT270="$(python3 "$AEGIS_ROOT/verify/checks/270.py" "$AEGIS_ROOT" 2>&1)"
RC270=$?
(( RC270 == 0 )) || { fail "the exercise of check 270 itself failed (rc $RC270): ${OUT270:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE270="${hit#SCOPE: }" ;;
        *)       D270="$D270 $hit;" ;;
    esac
done <<< "$OUT270"
printf '    %s\n' "${SCOPE270:-the scope was not reported}"
if [[ -n "$D270" ]]; then
    fail "the books do not reach the console:$D270"
else
    pass "Security carries the books (owed, unmeasured and clean images, each with its state), each project card its worst, the menu's dot reads them, and debt inside its window is drawn as the fine it is (${SCOPE270})"
fi
}
