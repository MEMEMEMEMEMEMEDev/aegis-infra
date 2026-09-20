# teeth for 214 — each red leaves one thing as the window left it, which
# is the half of this that never announces itself.
W214="$AEGIS_ROOT/lib/aegis/window.py"
U214="$AEGIS_ROOT/libexec/aegis-update"

# undone in the order they were made: two changes that depend on each
# other come back wrong
red_1() { python3 - "$W214" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            item = self._items.pop()'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''            item = self._items.pop(0)''', 1))
P
}

# one undo that fails stops the rest: the machine keeps two of the three
red_2() { python3 - "$W214" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            except Exception as e:                        # noqa: BLE001
                out.append({"restored": item["name"], "ok": False,
                            "what": item["what"], "error": f"{type(e).__name__}: {e}"})
        return out'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''            except Exception as e:                        # noqa: BLE001
                out.append({"restored": item["name"], "ok": False,
                            "what": item["what"], "error": f"{type(e).__name__}: {e}"})
                return out
        return out''', 1))
P
}

# an undo that raised is reported as done: the report says the machine
# came back and it did not
red_3() { python3 - "$W214" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''                out.append({"restored": item["name"], "ok": False,
                            "what": item["what"], "error": f"{type(e).__name__}: {e}"})'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''                out.append({"restored": item["name"], "ok": True,
                            "what": item["what"], "error": f"{type(e).__name__}: {e}"})''', 1))
P
}

# the restore moves out of the `finally` and into the happy path: it
# runs on the endings somebody thought of and not on the one it exists
# for
red_4() { python3 - "$U214" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
i = s.index('        for done in restore.run():')
j = s.index('        rep = j.close(outcome', i)
block = s[i:j]
assert 'restore:' in block, "re-aim this tooth"
s = s[:i] + s[j:]
anchor = '            steps.done("window:acceptance", nuevos=0, cegados=0,'
assert s.count(anchor) == 1, "re-aim this tooth"
p.write_text(s.replace(anchor, block + anchor, 1))
P
}

# the page comes down whatever the outcome: a broken instance goes back
# in front of the public
red_5() { python3 - "$U214" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            if outcome in ("accepted", "refused", "rolled-back"):'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''            if True:''', 1))
P
}

# the heartbeat gets silenced along with the rest: the alert that fires
# when the alerting stops working goes quiet during the one window where
# that is easiest to miss
red_6() { python3 - "$W214" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''SILENCEABLE = ("SitioDeInquilinoCaido", "SitioDeInquilinoSinSonda", "RegistryProbeFalla")'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''SILENCEABLE = ("SitioDeInquilinoCaido", "SitioDeInquilinoSinSonda", "DeadmanAegis")''', 1))
P
}

# the stack is not emptied: a second pass undoes everything twice
red_7() { python3 - "$W214" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        while self._items:
            item = self._items.pop()'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        for item in list(reversed(self._items)):''', 1))
P
}

# ── controls ──
# what an undo is CALLED changes; what it undoes does not
control_1() { python3 - "$W214" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''                out.append({"restored": item["name"], "ok": True, "what": item["what"]})'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''                out.append({"restored": item["name"], "ok": True, "what": item["what"],
                            "cuando": "on the way out"})''', 1))
P
}
# one more alert in the silenceable list is one more of the same kind
control_2() { python3 - "$W214" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''"SitioDeInquilinoSinSonda", "RegistryProbeFalla")'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''"SitioDeInquilinoSinSonda", "RegistryProbeFalla",
               "TargetDeScrapeCaido")''', 1))
P
}
# a comment about the three things is not the three things
control_3() { printf '\n# note: quiet, the silence and the clock are the three that stay silent.\n' >> "$W214"; }

# a completed rollback keeps the page up: the tree came back byte for
# byte, the acceptance passed, and the instance sits behind its own
# maintenance page until a human notices
red_8() { python3 - "$U214" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '            if outcome in ("accepted", "refused", "rolled-back"):'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '            if outcome in ("accepted", "refused"):', 1))
P
}
