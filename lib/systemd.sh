#!/usr/bin/env bash
# lib/systemd.sh — readings of systemd units that more than one caller
# needs: phase 05 (installing the clocks), the round (aegis check) and,
# in python, the update window (lib/aegis/window.py:timer_next_elapse
# says the same thing). Kept apart from common.sh so the round can
# source it alone.

# timer_next_elapse <scope> <unit> — prints the timer's next appointment
# and returns 0, or prints nothing and returns 1 when it has none.
# «Active» and «enabled» say nothing about whether a timer will ever
# fire again: OnUnitActiveSec re-arms only from a service run, so a
# timer that was restarted (an update window does that) can sit active
# with «NextElapse: n/a» for ever. Measured 2026-09-20. The reading is
# the union of the realtime and the monotonic appointment.
timer_next_elapse() {
    local scope="$1" unit="$2" rt mono
    rt="$(systemctl "$scope" show "$unit" -p NextElapseUSecRealtime --value 2>/dev/null)"
    mono="$(systemctl "$scope" show "$unit" -p NextElapseUSecMonotonic --value 2>/dev/null)"
    if [[ -n "$rt" ]]; then printf '%s\n' "$rt"; return 0; fi
    if [[ -n "$mono" && "$mono" != infinity ]]; then printf '%s\n' "$mono"; return 0; fi
    return 1
}

