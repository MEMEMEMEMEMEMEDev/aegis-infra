# teeth of check 270 — the console draws the books.
S270="$AEGIS_ROOT/lib/aegis/screens.py"
C270="$AEGIS_ROOT/libexec/aegis-console"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the console never asks for the books
red_1() { _sub "$C270" '           "vulns",
' ''; }

# Security forgets the section
red_2() { _sub "$S270" '             _vulns_section(reading_for(readings, "vulns"))]' '             ""]'; }

# the project card ignores its images' state
red_3() { _sub "$S270" '        state = worst({state, vstate})' '        pass'; }

# the menu's dot for Security is not fed by the books
red_4() { _sub "$S270" '    ("security", "Security", "/security", ("vulns",)),' '    ("security", "Security", "/security", ()),'; }

# an image nobody could scan disappears from the list of what is owed
red_5() { _sub "$S270" '    owed_or_unseen = [st for st in images if st.get("findings") or state_of(st) != FINE]' '    owed_or_unseen = [st for st in images if st.get("findings")]'; }

# debt inside its window is painted attention: a state the document does not carry
red_6() { _sub "$S270" "        rows.append(f'<tr data-state=\"{state}\"><td>{_pip(state)}</td><td>{link}</td>'" "        rows.append(f'<tr data-state=\"{ATTENTION if state == FINE else state}\"><td>{_pip(state)}</td><td>{link}</td>'"; }

# ── controls ──
control_1() { _sub "$S270" "'every day; one exploited in the wild has no window. '" "'every day; one exploited in the wild gets no window. '"; }
