# teeth of check 287 — the dossier of a run is born readable by its owner only.
L287="$AEGIS_ROOT/libexec/aegis-init-log"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the wrapper as it was until 2026-10-14: script(1) creates the dossier under the operator's umask
red_1() { _sub "$L287" '( umask 077; : > "$LOG" )   # born 0600: script(1) truncates it and keeps the mode
' ''; }

# the runs dir keeps the mode the umask gives it
red_2() { _sub "$L287" 'mkdir -p "$RUNS"; chmod 700 "$RUNS"
' 'mkdir -p "$RUNS"
'; }

# the dossier is tightened only after the run
red_3() { _sub "$L287" '( umask 077; : > "$LOG" )   # born 0600: script(1) truncates it and keeps the mode
if script -qefc "$CMD" "$LOG"; then
' 'if script -qefc "$CMD" "$LOG"; then
    chmod 600 "$LOG"
'; }

# the whole wrapper under umask 077: the init itself would inherit it
red_4() { _sub "$L287" '( umask 077; : > "$LOG" )   # born 0600: script(1) truncates it and keeps the mode
' 'umask 077
: > "$LOG"
'; }

# ── controls ──
control_1() { _sub "$L287" '# readable by every account on the host (review of 2026-10-13, A-9).' '# readable by every account of the host (review of 2026-10-13, A-9).'; }
control_2() { _sub "$L287" '# born 0600: script(1) truncates it and keeps the mode' '# born 0600: script(1) truncates it and leaves the mode'; }
