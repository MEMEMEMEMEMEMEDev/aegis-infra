# title: every host family aegis has code for has its branch wherever the host differs by family
# origin: new in v3 — 2026-09-23, the distro line: a family that passes the door and misses one branch dies halfway, which is the CachyOS shape all over again
check() {
D241=""
[[ -f "$AEGIS_ROOT/verify/checks/241.py" ]] || { fail "check 241 has no sidecar"; return; }
OUT241="$(python3 "$AEGIS_ROOT/verify/checks/241.py" "$AEGIS_ROOT" 2>&1)"
RC241=$?
(( RC241 == 0 )) || { fail "the scan of check 241 itself failed (rc $RC241): ${OUT241:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE241="${hit#SCOPE: }" ;;
        *)       D241="$D241 $hit;" ;;
    esac
done <<< "$OUT241"
printf '    %s\n' "${SCOPE241:-the scope was not reported}"
if [[ -n "$D241" ]]; then
    fail "a family with code would pass the door and stop halfway:$D241"
else
    pass "every family with code has its CA anchor and refresh, its base packages, its tofu and its clock unit (${SCOPE241})"
fi
}
