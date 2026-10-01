# teeth of check 265 — app rebase brings the pipeline.
A265="$AEGIS_ROOT/libexec/aegis-app"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# rebase as it was: FROMs only, the pipeline stays as planted
red_1() { _sub "$A265" '            shutil.copyfile(derived, mine)' '            pass'; }

# a dry run that writes
red_2() { _sub "$A265" '        elif write:
            shutil.copyfile(derived, mine)' '        elif True:
            shutil.copyfile(derived, mine)'; }

# ── controls ──
control_1() { _sub "$A265" '"brought to the pipeline this platform derives"' '"now the pipeline this platform derives"'; }
