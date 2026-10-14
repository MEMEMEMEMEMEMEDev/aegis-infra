# title: the dossier of a run is born readable by its owner only, whatever the operator's umask
# origin: new in v3 — 2026-10-13 review (A-9): script(1) created the dossier under the default umask, 0644 in a 0755 dir, readable by every account on the host, with the whole run's stderr inside
check() {
D287=""
[[ -f "$AEGIS_ROOT/verify/checks/287.py" ]] || { fail "check 287 has no sidecar"; return; }
OUT287="$(python3 "$AEGIS_ROOT/verify/checks/287.py" "$AEGIS_ROOT" 2>&1)"
RC287=$?
(( RC287 == 0 )) || { fail "the exercise of check 287 itself failed (rc $RC287): ${OUT287:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE287="${hit#SCOPE: }" ;;
        *)       D287="$D287 $hit;" ;;
    esac
done <<< "$OUT287"
printf '    %s\n' "${SCOPE287:-the scope was not reported}"
if [[ -n "$D287" ]]; then
    fail "the dossier of a run can be read by other accounts on the host:$D287"
else
    pass "aegis init-log creates the runs dir 0700 and the dossier 0600 before script(1) writes it, under a permissive umask too, and the init's rc, both streams and the path-first line are kept (${SCOPE287})"
fi
}
