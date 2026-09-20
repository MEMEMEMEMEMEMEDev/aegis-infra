# teeth for 219 — each red puts the trap back, in one command or
# another. The first is the line that killed a window.
U219="$AEGIS_ROOT/libexec/aegis-update"
D219F="$AEGIS_ROOT/libexec/aegis-data"

# the line itself, verbatim
red_1() { python3 - "$U219" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''                steps.wrong("window:maintenance-no-effect",
                            **{**seen,'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''                steps.wrong("window:maintenance-no-effect", **seen,
                            **{''', 1).replace('"consecuencia": "a page nobody sees',
                                               'consecuencia="a page nobody sees', 1))
P
}

# the same trap in another command: the family is not one file's
red_2() { python3 - "$D219F" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'steps.wrong(f"backup:{org}", **{**data, "why": "no-copy-at-the-destination"})'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, 'steps.wrong(f"backup:{org}", **data, why="no-copy-at-the-destination")', 1))
P
}

# two dictionaries splatted into one entry: they can share a key and
# nothing says which was meant to win
red_3() { python3 - "$U219" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'j.note("layer", **{**layer.as_data(), **{k: v for k, v in did.items()'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, 'j.note("layer", **layer.as_data(), **{k: v for k, v in did.items()', 1))
P
}

# the check stops looking at the commands at all
red_4() { python3 - "$AEGIS_ROOT/verify/checks/219.py" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    if not text.startswith("#!/usr/bin/env python3"):'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    if not text.startswith("#!/usr/bin/env nothing"):', 1))
P
}

# ── controls ──
# a payload gains one more key; nothing is named beside it
control_1() { python3 - "$U219" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '"consecuencia": "a page nobody sees'
assert s.count(old) == 1
p.write_text(s.replace(old, '"cuando": "after the page went up", "consecuencia": "a page nobody sees', 1))
P
}
# naming keywords with no dictionary beside them is the ordinary case
control_2() { python3 - "$U219" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        steps.already("window:maintenance-off-by-choice",'
assert s.count(old) == 1
p.write_text(s.replace(old, '        steps.already("window:maintenance-off-by-choice", cuando="al abrir",', 1))
P
}
# a comment showing the forbidden shape is prose
control_3() { printf '\n# note: never write steps.wrong(name, **payload, por_que="…") — see check 219.\n' >> "$U219"; }

# and the call that died, put back as it was
red_5() { python3 - "$U219" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    ctx.j.note("sync", **{**settled, "app": app, "rc": rc})'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    ctx.j.note("sync", app=app, rc=rc, **settled)', 1))
P
}
