# title: no tool that lives only in sbin is called bare, where a user's PATH on Debian cannot find it
# origin: new in v3 — 2026-09-23, lab-debian13: /usr/sbin is on root's and sudo's PATH there, not on a user's; a bare sysctl in phase 87 would have read «command not found» as a ceiling of 0
check() {
# THE CLASS, not the one line: every call to a tool Debian keeps in
# /usr/sbin either goes through sudo (secure_path finds it), names its
# path, or reads /proc instead. The tools are the ones MEASURED sbin-only
# on Debian 13, listed in the sidecar with that measurement.
D239=""
[[ -f "$AEGIS_ROOT/verify/checks/239.py" ]] || { fail "check 239 has no sidecar"; return; }
OUT239="$(python3 "$AEGIS_ROOT/verify/checks/239.py" "$AEGIS_ROOT" 2>&1)"
RC239=$?
(( RC239 == 0 )) || { fail "the scan of check 239 itself failed (rc $RC239): ${OUT239:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE239="${hit#SCOPE: }" ;;
        *)       D239="$D239 $hit;" ;;
    esac
done <<< "$OUT239"
printf '    %s\n' "${SCOPE239:-the scope was not reported}"
if [[ -n "$D239" ]]; then
    fail "a tool a Debian user's PATH cannot find is called bare:$D239"
else
    pass "every sbin-only tool goes through sudo, its path, or /proc (${SCOPE239})"
fi
}
