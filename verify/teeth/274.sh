# teeth of check 274 — no variable declared twice in one scope chain.
W274="$AEGIS_ROOT/seed/platform/image-watch/Jenkinsfile"
A274="$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the watch as 9468a84 shipped it: the app pass declares `mrc` again inside the serving loop
red_1() { _sub "$W274" '              def irc = -1' '              def mrc = -1'; }

# a loop variable reused as a `def` inside the loop it opens
red_2() { _sub "$W274" '              int crit2 = 0' '              int crit2 = 0
              def t = null'; }

# ── controls ──
# two sibling blocks may each declare their own name
control_1() { _sub "$W274" '              int crit2 = 0' '              if (true) { def sibling = 1 }
              if (true) { def sibling = 2 }
              int crit2 = 0'; }
