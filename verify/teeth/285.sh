# teeth of check 285 — the copy of the age key the operator reads dies with the phase.
S285="$AEGIS_ROOT/lib/secrets.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the ceremony as it was until 2026-10-14: the copy outside the shredded dir
red_1() { _sub "$S285" '    local shm_out="$SECRETS_TMP/resguardo"
' '    local shm_out="/dev/shm/aegis-resguardo-$$"
'; }

# no EXIT trap: a die leaves the tmpfs dir, copy included
red_2() { _sub "$S285" "    trap 'secrets_cleanup' EXIT
" ''; }

# the cleanup removes the dir without shredding what is in it
red_3() { _sub "$S285" '    find "$SECRETS_TMP" -type f -exec shred -u {} \;
' ''; }

# the precondition is not stated: with no tmpfs, the copy would go to /resguardo
red_4() { _sub "$S285" '    : "${SECRETS_TMP:?ceremony_backup needs secrets_workdir first: the copy the operator reads lives in the tmpfs of the phase}"
' ''; }

# no INT/TERM trap: a Ctrl-C at the pause kills the shell without the cleanup
red_5() { _sub "$S285" "    trap 'secrets_cleanup; exit 130' INT TERM
" ''; }

# ── controls ──
control_1() { _sub "$S285" 'die in the validator or a Ctrl-C left the root of trust in the clear' 'die in the validator or a Ctrl-C left the root of trust exposed'; }
control_2() { _sub "$S285" 'the copy the operator reads lives in the tmpfs of the phase}' 'the copy the operator reads is written into the tmpfs of the phase}'; }
