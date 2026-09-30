# teeth of check 261 — the staging area is ignored by the platform repo.
G261="$AEGIS_ROOT/seed/platform/.gitignore"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the .gitignore as it was until 2026-09-30
red_1() { _sub "$G261" '
.aegis-app/
' '
'; }

# a pattern that only LOOKS right: the line is there, commented out
red_2() { _sub "$G261" '
.aegis-app/
' '
# .aegis-app/
'; }

# ── controls ──
# the same rule anchored at the root is the same rule
control_1() { _sub "$G261" '
.aegis-app/
' '
/.aegis-app/
'; }
