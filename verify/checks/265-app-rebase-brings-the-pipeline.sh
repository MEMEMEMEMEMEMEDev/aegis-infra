# title: `aegis app rebase` brings an app's Jenkinsfile to the pipeline the platform derives (written, never pushed)
# origin: new in v3 — 2026-09-30, the Arch lab VM: the platform changed the tenant scan and the portfolio kept the old pipeline until it was copied by hand
check() {
# A Jenkinsfile was planted once and never updated. The sidecar RUNS
# app rebase over a controlled checkout.
D265=""
[[ -f "$AEGIS_ROOT/verify/checks/265.py" ]] || { fail "check 265 has no sidecar"; return; }
OUT265="$(python3 "$AEGIS_ROOT/verify/checks/265.py" "$AEGIS_ROOT" 2>&1)"
RC265=$?
(( RC265 == 0 )) || { fail "the exercise of check 265 itself failed (rc $RC265): ${OUT265:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE265="${hit#SCOPE: }" ;;
        *)       D265="$D265 $hit;" ;;
    esac
done <<< "$OUT265"
printf '    %s\n' "${SCOPE265:-the scope was not reported}"
if [[ -n "$D265" ]]; then
    fail "an app's pipeline does not follow the platform's:$D265"
else
    pass "app rebase brings each repo's Jenkinsfile to the derived one, says so dry, and is a no-op the second time (${SCOPE265})"
fi
}
