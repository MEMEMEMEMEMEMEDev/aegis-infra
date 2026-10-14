# title: the copy of the age key the operator reads from another terminal dies with the phase, however the phase ends
# origin: new in v3 — 2026-10-13 review (A-9): the copy sat at /dev/shm/aegis-resguardo-$$, outside the shredded tmpfs dir, and was removed only after a successful validation — a wrong paste, a die or a Ctrl-C left the root of trust in the clear until reboot
check() {
D285=""
[[ -f "$AEGIS_ROOT/verify/checks/285.py" ]] || { fail "check 285 has no sidecar"; return; }
OUT285="$(python3 "$AEGIS_ROOT/verify/checks/285.py" "$AEGIS_ROOT" 2>&1)"
RC285=$?
(( RC285 == 0 )) || { fail "the exercise of check 285 itself failed (rc $RC285): ${OUT285:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE285="${hit#SCOPE: }" ;;
        *)       D285="$D285 $hit;" ;;
    esac
done <<< "$OUT285"
printf '    %s\n' "${SCOPE285:-the scope was not reported}"
if [[ -n "$D285" ]]; then
    fail "the root of trust can be left in the clear in /dev/shm:$D285"
else
    pass "the copy the operator reads lives inside the phase's tmpfs dir, which the EXIT/INT/TERM traps shred: a failed validation, an abort at the pause and a TERM all leave nothing behind (${SCOPE285})"
fi
}
