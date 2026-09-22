# title: a server image is not a desktop: graphical.target alone does not make a machine shared
# origin: new in v3 — 2026-09-22, the first Vultr VM of the lab boots into graphical.target with no display manager, and aegis called it shared
check() {
# The probe behind `aegis host` decides whether a human shares the
# machine, and from that how much memory aegis leaves the desktop. It
# took `graphical.target` alone as proof, and cloud images boot into it
# with nothing graphical installed. A display manager is what puts a
# login screen in front of somebody. Driven in the sidecar (228.py).
D228=""
[[ -f "$AEGIS_ROOT/verify/checks/228.py" ]] || { fail "check 228 has no sidecar"; return; }
OUT228="$(python3 "$AEGIS_ROOT/verify/checks/228.py" "$AEGIS_ROOT" 2>&1)"
RC228=$?
(( RC228 == 0 )) || { fail "the scan of check 228 itself failed (rc $RC228): ${OUT228:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE228="${hit#SCOPE: }" ;;
        *)       D228="$D228 $hit;" ;;
    esac
done <<< "$OUT228"
printf '    %s\n' "${SCOPE228:-the scope was not reported}"
if [[ -n "$D228" ]]; then
    fail "the probe misjudges who shares the machine:$D228"
else
    pass "a cloud image with graphical.target and no display manager is not shared; a desktop is, seated or waiting; an unreadable display manager stays timid (${SCOPE228})"
fi
}
