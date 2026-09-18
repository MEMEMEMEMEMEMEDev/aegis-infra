# teeth for 212 — the record of a window has to be readable afterwards.
# Each red turns the record into a number, or loses it on the way out.
W212="$AEGIS_ROOT/lib/aegis/window.py"
U212="$AEGIS_ROOT/libexec/aegis-update"

# the report counts the commits instead of naming them: «four commits»
# answers nothing at midnight
red_1() { python3 - "$W212" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''                  "commits": [{"sha": c["sha"], "subject": c.get("subject", ""),
                               "pin": c.get("pin", ""), "layer": c.get("layer")}
                              for c in self.commits()],'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''                  "commits": len(self.commits()),''', 1))
P
}

# the journal stops recognising its own commit entries: the report
# comes out empty about a window that changed four things
red_2() { python3 - "$W212" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        return [e for e in self.entries() if e.get("kind") == "commit" and e.get("sha")]'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        return [e for e in self.entries() if e.get("kind") == "commited"]''', 1))
P
}

# `status` drops the commits on the way out: the report holds them and
# nothing that reads the command ever sees them
red_3() { python3 - "$U212" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        f"window:{wid}", **{k: v for k, v in doc.items() if k != "steps"})'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        f"window:{wid}", **{k: v for k, v in doc.items()
                            if k not in ("steps", "commits")})''', 1))
P
}

# a subject is no longer written beside the sha: the reader has to open
# git to find out what the window did
red_4() { python3 - "$W212" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''                  "commits": [{"sha": c["sha"], "subject": c.get("subject", ""),'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''                  "commits": [{"sha": c["sha"], "subject": "",''', 1))
P
}

# a window that changed nothing says nothing at all: zero steps is rc 2,
# and «it changed nothing» stops being distinguishable from «I could not
# tell you»
red_5() { python3 - "$U212" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    outcome = doc.get("outcome") or "?"'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    if not doc.get("commits"):
        sys.exit(0)
    outcome = doc.get("outcome") or "?"''', 1))
P
}

# ── controls ──
# the journal gains one more field per commit: one more thing written,
# nothing lost
control_1() { python3 - "$W212" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''                               "pin": c.get("pin", ""), "layer": c.get("layer")}'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''                               "pin": c.get("pin", ""), "layer": c.get("layer"),
                               "cuando": c.get("at", "")}''', 1))
P
}
# the narration of `status` changes wording; the document does not
control_2() { python3 - "$U212" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        print(f"window {wid}: {outcome}", file=sys.stderr)'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''        print(f"the last window ({wid}) ended: {outcome}", file=sys.stderr)''', 1))
P
}
# a comment about the record is not the record
control_3() { printf '\n# note: the report names each commit so that the reader can revert one by hand.\n' >> "$W212"; }
