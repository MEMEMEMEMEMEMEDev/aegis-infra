# teeth for 224 — each red brings back a clock that lies.
PH224="$AEGIS_ROOT/init/phases/05-host.sh"
TM224="$AEGIS_ROOT/share/systemd/aegis-backup.timer"
LB224="$AEGIS_ROOT/lib/systemd.sh"
CK224="$AEGIS_ROOT/libexec/aegis-check"
WN224="$AEGIS_ROOT/lib/aegis/window.py"

_sub224() { python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the timer loses its calendar: a restart leaves it with no next run (2026-09-20)
red_1() { _sub224 "$TM224" "OnCalendar=daily" "# OnCalendar=daily"; }
# the phase stops installing the units: back to the README (2026-09-16)
red_2() { _sub224 "$PH224" 'run_cmd install -m 644 "$AEGIS_ROOT/share/systemd/$_c.service" "$AEGIS_ROOT/share/systemd/$_c.timer" "$USER_UNITS/"' ':'; }
# no linger: the clocks stop when the operator logs out
red_3() { _sub224 "$PH224" 'run_cmd sudo loginctl enable-linger "$USER"' ':'; }
# the phase gates on «enabled» only
red_4() { _sub224 "$PH224" "timer_next_elapse --user \"\$c.timer\" >/dev/null || return 1" "systemctl --user is-active \"\$c.timer\" >/dev/null || return 1"; }
# the window puts the timer back and stops reading a next run (error nº 13)
red_5() { python3 - "$WN224" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
m = re.search(r"    nxt = timer_next_elapse\(unit, scope\)\n    if nxt is None:\n(?:.*\n)*?    return \{\"unidad\": unit, \"ambito\": scope, \"proxima\": nxt\}\n", s)
assert m, "re-aim this tooth"
p.write_text(s.replace(m.group(0), "    return {\"unidad\": unit, \"ambito\": scope}\n", 1))
PY
}
# the round stops asking the clocks
red_6() { _sub224 "$CK224" 'elif _next="$(timer_next_elapse --user "$_clock.timer")"; then' 'elif systemctl --user is-active "$_clock.timer" >/dev/null 2>&1; then _next=active;'; }
# the helper takes monotonic «infinity» for an appointment
red_7() { _sub224 "$LB224" 'if [[ -n "$mono" && "$mono" != infinity ]]; then' 'if [[ -n "$mono" ]]; then'; }
# the helper takes an empty realtime for an appointment
red_8() { _sub224 "$LB224" 'if [[ -n "$rt" ]]; then printf' 'if true; then printf'; }
# the phase no longer links share/ where the units say it is
red_9() { _sub224 "$PH224" 'run_cmd sudo ln -sfn "$AEGIS_ROOT/share" /usr/local/share/aegis' ':'; }

# ── controls ──
# a different calendar is still a calendar
# the gate as it was on 2026-09-22: measured the second after enable --now
red_10() { _sub224 "$PH224" '        wait_for 120 3 "the three user clocks have a next run" _clocks_scheduled' '        _clocks_scheduled'; }

control_1() { _sub224 "$TM224" "OnCalendar=daily" "OnCalendar=*-*-* 03:00:00"; }
# the phase's prose is prose
control_2() { _sub224 "$PH224" "# linger: or the clocks stop the moment the operator logs out" "# linger, so the clocks keep running after logout"; }
# a fourth clock installed the same way is legal
control_3() { _sub224 "$PH224" 'CLOCKS=(aegis-backup aegis-host-metrics aegis-update-notice)' 'CLOCKS=(aegis-backup aegis-host-metrics aegis-update-notice)
: extra-clock-placeholder'; }
