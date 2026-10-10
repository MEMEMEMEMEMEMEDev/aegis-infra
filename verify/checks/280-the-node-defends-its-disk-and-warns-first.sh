# title: the node defends its disk (the kubelet's disk eviction is not switched off by aegis's memory margin) and warns before it has to
# origin: new in v3 — plan/19 B-6 (2026-09-24): a filling disk met no eviction and no alert; 2026-10-10: the memory-only eviction-hard had switched the kubelet's disk defaults off
check() {
D280=""
[[ -f "$AEGIS_ROOT/verify/checks/280.py" ]] || { fail "check 280 has no sidecar"; return; }
OUT280="$(python3 "$AEGIS_ROOT/verify/checks/280.py" "$AEGIS_ROOT" 2>&1)"
RC280=$?
(( RC280 == 0 )) || { fail "the exercise of check 280 itself failed (rc $RC280): ${OUT280:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE280="${hit#SCOPE: }" ;;
        *)       D280="$D280 $hit;" ;;
    esac
done <<< "$OUT280"
printf '    %s\n' "${SCOPE280:-the scope was not reported}"
if [[ -n "$D280" ]]; then
    fail "the node's disk is undefended or unwatched:$D280"
else
    pass "the kubelet drop-in keeps the disk thresholds next to the memory margin, phase 20 reads them back from the running kubelet, and an alert warns at 20% free (${SCOPE280})"
fi
}
