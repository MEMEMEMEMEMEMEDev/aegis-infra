# teeth for 208 — a refusal that arrives after the page went up is not a
# refusal. Each red either lets a hook run too early, or hides one of
# the reasons to stop.
W208="$AEGIS_ROOT/lib/aegis/window.py"
U208="$AEGIS_ROOT/libexec/aegis-update"

# the refusals are collected and the window carries on anyway: the hook
# runs over a repo full of somebody else's work
red_1() { python3 - "$U208" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        if narrate:
            print(f"\\n{len(bad)} refusal(s): the window does not open, and nothing was "
                  f"touched", file=sys.stderr)
        steps.finish()'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        if narrate:
            print(f"\\n{len(bad)} refusal(s)", file=sys.stderr)''', 1))
P
}

# only the first reason is reported: the operator meets the list one
# night at a time
red_2() { python3 - "$W208" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    if not hooks.coherent:'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    if out:
        return out
    if not hooks.coherent:''', 1))
P
}

# uncommitted work stops being a reason to stop
red_3() { python3 - "$W208" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        d = dirty(root)
        if d:'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        d = dirty(root)
        if False:''', 1))
P
}

# a half-configured pair is let through: the page goes up and nothing
# knows how to take it down
red_4() { python3 - "$W208" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        return bool(self.on) == bool(self.off)'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        return True''', 1))
P
}

# the photo fails and the window goes on: the page goes up over an
# instance nobody described
red_5() { python3 - "$U208" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        steps.not_evaluable("window:photo", por_que=str(e),
                            nota="the window did not open: with no before there is "
                                 "nothing for a rollback to come back to")
        steps.finish()'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        steps.not_evaluable("window:photo", por_que=str(e),
                            nota="the window did not open: with no before there is "
                                 "nothing for a rollback to come back to")
        before = {"round": {"doc": {"steps": []}, "rc": 0}}''', 1))
P
}

# the dry run runs the hooks: --yes stops meaning anything
red_6() { python3 - "$U208" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    if not yes:
        # THE REHEARSAL IS NOT A SHORTER VERSION.'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    if not yes:
        hooks.run("on")
        # THE REHEARSAL IS NOT A SHORTER VERSION.''', 1))
P
}

# ── controls ──
# the wording of a reason changes; the reason does not
control_1() { python3 - "$W208" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'f"commit or stash them first: '
assert s.count(old) == 1
p.write_text(s.replace(old, 'f"commit them or put them aside first: ', 1))
P
}
# a reason that never triggers on a healthy fixture is still just a reason
control_2() { python3 - "$W208" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    if budget_minutes is not None and budget_minutes < 30:'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''    if not root.name:
        out.append(Refusal("platform-unnamed", "the platform path has no name at all",
                           "point PLATFORM_DIR at a directory"))
    if budget_minutes is not None and budget_minutes < 30:''', 1))
P
}
# a comment naming the hooks is not a hook
control_3() { printf '\n# note: MAINTENANCE_ON and MAINTENANCE_OFF are the operator s, not the product s.\n' >> "$W208"; }
