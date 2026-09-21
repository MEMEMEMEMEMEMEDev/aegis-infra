# title: the instance's clocks are installed by a phase, and a clock is a next appointment, not an «active» unit
# origin: new in v3 — 2026-09-16 the backup timer had never been installed; 2026-09-20 it sat active with no next run
check() {
# TWO WAYS A CLOCK LIES, both measured on the house machine:
#   · it was never installed. The units shipped in share/systemd/ and
#     a README said how to copy them; no phase did, so the copies were
#     three days old while every dashboard looked healthy (2026-09-16).
#   · it is active, enabled, and will never fire. OnUnitActiveSec
#     re-arms only from a service run; an update window stops and
#     starts the timer, and systemd shows «NextElapse: n/a» for the
#     rest of the day (2026-09-20, error nº 13 of the window protocol).
# So: phase 05 installs the three user units, derives backup.env and
# enables linger; the backup timer carries OnCalendar beside the
# interval; and every reader — the phase's gate, the round, the window's
# restore — asks for a NEXT RUN through one helper, never for «active».
D224=""
[[ -f "$PHASES/05-host.sh" ]] || { skip "there is no phase 05"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/224.py" ]] || { fail "check 224 has no sidecar"; return; }

OUT224="$(python3 "$AEGIS_ROOT/verify/checks/224.py" "$AEGIS_ROOT" 2>&1)"
RC224=$?
if (( RC224 != 0 )); then
    fail "the exercise of check 224 itself failed (rc $RC224): $OUT224"
    return
fi
SCOPE224=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE224="${hit#SCOPE: }" ;;
        *)       D224="$D224 $hit;" ;;
    esac
done <<< "$OUT224"

printf '    %s\n' "${SCOPE224:-the scope was not reported}"
if [[ -n "$D224" ]]; then
    fail "a clock can still be missing or silent:$D224"
else
    pass "phase 05 installs the three user clocks with a derived backup.env and linger, the backup timer has a calendar, and the phase, the round and the window all ask for a next run ($SCOPE224)"
fi
}
