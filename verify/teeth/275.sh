# teeth of check 275 — --help after a verb is help, and writes nothing.
S275="$AEGIS_ROOT/libexec/aegis-state"
D275="$AEGIS_ROOT/libexec/aegis-dev"
B275="$AEGIS_ROOT/libexec/state/backup"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# aegis state as it was: --help after the verb reaches the verb's script (the «--help» bundle)
red_1() { _sub "$S275" '    case "$_a" in -h|--help) usage; exit 0 ;; esac' '    :'; }

# the same hole in aegis dev
red_2() { _sub "$D275" '    case "$_a" in -h|--help) usage; exit 0 ;; esac' '    :'; }

# state backup writes a flag as its output file
red_3() { _sub "$B275" '    -*) printf' '    --never-a-flag-*) printf'; }

# ── controls ──
control_1() { _sub "$B275" "this command takes no flags" "this command takes no options"; }
