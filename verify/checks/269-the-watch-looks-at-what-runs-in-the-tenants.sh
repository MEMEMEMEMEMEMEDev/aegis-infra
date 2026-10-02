# title: the watch looks at what runs in the tenants: each contract's repo, the digest its overlay deploys, read-only
# origin: new in v3 — 2026-10-02, plan/21 stage 6: S11 of images.md — the watch scanned bases and mirrors and never the app images built on them, so an app built on last month's base carried its CVEs unseen
check() {
# The sidecar RUNS the apps stage's two shell blocks (as Groovy hands them
# to the shell) over fixture contracts and a fixture overlay, and reads
# the stage for what it may and may not do.
D269=""
[[ -f "$AEGIS_ROOT/verify/checks/269.py" ]] || { fail "check 269 has no sidecar"; return; }
OUT269="$(python3 "$AEGIS_ROOT/verify/checks/269.py" "$AEGIS_ROOT" 2>&1)"
RC269=$?
(( RC269 == 0 )) || { fail "the exercise of check 269 itself failed (rc $RC269): ${OUT269:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE269="${hit#SCOPE: }" ;;
        *)       D269="$D269 $hit;" ;;
    esac
done <<< "$OUT269"
printf '    %s\n' "${SCOPE269:-the scope was not reported}"
if [[ -n "$D269" ]]; then
    fail "what runs in the tenants is not watched:$D269"
else
    pass "every repo a contract names is read for the digest its overlay deploys, scanned and kept in the books as KIND=app, and the stage never pushes (${SCOPE269})"
fi
}
