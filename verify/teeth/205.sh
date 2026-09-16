# teeth for 205 — every screen keeps the invariants. Each red breaks
# one, on a screen that is NOT the overview, so that 122 and 127 alone
# would not have caught it.
S205="$AEGIS_ROOT/lib/aegis/screens.py"

# the deployments screen decides its verdict over nothing: always fine
red_1() { python3 - "$S205" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''def deployments(readings):
    v = verdict_of(readings)'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''def deployments(readings):
    v = FINE''', 1))
P
}

# the domains screen draws a hostname hatched when the edge was simply
# not consulted: a state nobody emitted
red_2() { python3 - "$S205" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        if edge is None:
            verdict = '<span class="faint">the edge was not consulted</span>\''''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        if edge is None:
            verdict = _chip(UNSEEN, "not consulted")''', 1))
P
}

# the project page's verdict ignores its readings
red_3() { python3 - "$S205" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    v = verdict_of(readings)
    ctx = list(instance or [])'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    v = FINE
    ctx = list(instance or [])''', 1))
P
}

# the round's subset on a concept page is drawn without its age
red_4() { python3 - "$S205" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    return _section(reading, "What the round says about it", body, states, "round",
                    icon="pulse")'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    return _section(reading, "What the round says about it", body, states, "round",
                    icon="pulse").replace('<p class="age">', '<p class="when">', 1)''', 1))
P
}

# ── controls ──
# the sentences under each page are reworded: words are not the contract
control_1() { sed -i 's/Every push to a project.s repository becomes a build\./Each push to a repository becomes a build./' "$S205"; }
# the groups of the menu are reordered
control_2() { python3 - "$S205" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''MENU = (("Build & ship", ("projects", "deployments", "domains")),
        ("Run", ("traffic", "storage", "plans")),
        ("Platform", ("security", "machine", "health")))'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''MENU = (("Platform", ("security", "machine", "health")),
        ("Build & ship", ("projects", "deployments", "domains")),
        ("Run", ("traffic", "storage", "plans")))''', 1))
P
}
# a comment is added
control_3() { printf '\n# note: every screen is a function of the readings and nothing else.\n' >> "$S205"; }
