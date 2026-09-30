# title: an exception is scoped to the paths the scan itself named, and an accepted risk says it was not measured, is bounded by the policy and never covers what is exploited in the wild
# origin: new in v3 — 2026-09-28, Rob's instance (his H-06): ten --allow on node:22.23.1-alpine scoped to «Node.js (node-pkg)» and the same ten CVEs came back; plan/21 adds the accepted kind
check() {
# The scope of an npm exception is each package.json the scan named,
# which trivy's table never prints. The sidecar RUNS aegis-image's scope
# reader and exception writer on the cases that define them, and the
# flag parser on --allow and --accept given together.
D258=""
[[ -f "$AEGIS_ROOT/verify/checks/258.py" ]] || { fail "check 258 has no sidecar"; return; }
OUT258="$(python3 "$AEGIS_ROOT/verify/checks/258.py" "$AEGIS_ROOT" 2>&1)"
RC258=$?
(( RC258 == 0 )) || { fail "the exercise of check 258 itself failed (rc $RC258): ${OUT258:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE258="${hit#SCOPE: }" ;;
        *)       D258="$D258 $hit;" ;;
    esac
done <<< "$OUT258"
printf '    %s\n' "${SCOPE258:-the scope was not reported}"
if [[ -n "$D258" ]]; then
    fail "an exception is not scoped or written the way the scan and the policy say:$D258"
else
    pass "an exception names each path the scan reported (npm by package.json, OS by *.tar target), an accepted risk says so and is bounded by the policy and refused for KEV, and one CVE is either measured or accepted (${SCOPE258})"
fi
}
