# title: every package the host gets goes through lib/pkg.sh, by a name its table knows, and the table says the right thing per family
# origin: new in v3 — 2026-09-23, the distro line: apt-get with Ubuntu's names in six places; Debian shares both, Arch neither
check() {
D240=""
[[ -f "$AEGIS_ROOT/verify/checks/240.py" ]] || { fail "check 240 has no sidecar"; return; }
OUT240="$(python3 "$AEGIS_ROOT/verify/checks/240.py" "$AEGIS_ROOT" 2>&1)"
RC240=$?
(( RC240 == 0 )) || { fail "the scan of check 240 itself failed (rc $RC240): ${OUT240:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE240="${hit#SCOPE: }" ;;
        *)       D240="$D240 $hit;" ;;
    esac
done <<< "$OUT240"
printf '    %s\n' "${SCOPE240:-the scope was not reported}"
if [[ -n "$D240" ]]; then
    fail "a package can reach the host outside the one table:$D240"
else
    pass "the manager is named only in lib/pkg.sh, every installed name has its row and every row a use, and the translation was driven per family (${SCOPE240})"
fi
}
