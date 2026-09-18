# teeth for 213 — the two lists must not drift. Each red is a drift that
# would not go red on its own: it would go GREEN and mean nothing.
W213="$AEGIS_ROOT/lib/aegis/window.py"
U213="$AEGIS_ROOT/libexec/aegis-update"

# a class loses its layer: the window walks past it every month
red_1() { python3 - "$W213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    Layer(5, "the images written by hand", ("raw-image",), ("pods", "argocd"),'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    Layer(5, "the images written by hand", (), ("pods", "argocd"),''', 1))
P
}

# a layer is judged by a section the round does not have: its acceptance
# compares an empty set and passes always
red_2() { python3 - "$W213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''          ("argocd", "stuck syncs", "pods", "certificates"),'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''          ("argocd", "synchronisations", "pods", "certificates"),''', 1))
P
}

# a layer stops saying how it is undone
red_3() { python3 - "$W213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''          "revert the line of images.txt; the registry keeps the previous digest", 30,'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''          "", 30,''', 1))
P
}

# two layers claim the same class: applied twice, reverted once
red_4() { python3 - "$W213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    Layer(8, "the CI's pod templates", ("jenkinsfile",),'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    Layer(8, "the CI's pod templates", ("jenkinsfile", "chart"),''', 1))
P
}

# a layer is declared, priced and counted, and nothing applies it
red_5() { python3 - "$U213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    if layer.number == 8:
        return layer_jenkinsfiles(ctx, layer, mine)'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    if layer.number == 88:
        return layer_jenkinsfiles(ctx, layer, mine)''', 1))
P
}

# a layer loses its estimate: the budget can no longer refuse to start it
red_6() { python3 - "$W213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''          "revert the pin and re-run phase 05 with AEGIS_HOST_ALIGN=1", 15),'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''          "revert the pin and re-run phase 05 with AEGIS_HOST_ALIGN=1", 0),''', 1))
P
}

# a layer is judged by the WHOLE round: every layer answers for the
# fault the one before it left, and the rollback undoes the wrong thing
red_7() { python3 - "$W213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    new = [n for n in cmp_["nuevos"] if n["seccion"] in mine]\n    blind = [n for n in cmp_["cegados"] if n["seccion"] in mine]'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    new = list(cmp_["nuevos"])\n    blind = list(cmp_["cegados"])', 1))
P
}

# a reading that stopped being measurable is accepted: the layer did not
# pass its section, it stopped asking about it
red_8() { python3 - "$W213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    return {"capa": layer.number, "acepta": not new and not blind,'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    return {"capa": layer.number, "acepta": not new,', 1))
P
}

# the budget always says there is room: a layer begins a walk it cannot
# finish, which is the one moment there is nothing good to do
red_9() { python3 - "$W213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    def room_for(self, layer):\n        return self.left >= layer.minutes'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    def room_for(self, layer):\n        return True', 1))
P
}

# the window stops asking the budget: the estimates are written down and
# nothing reads them
red_10() { python3 - "$U213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '            if not ctx.budget.room_for(layer):'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '            if False:', 1))
P
}

# ── controls ──
# a layer's name reads better; nothing it owns or is judged by moves
control_1() { python3 - "$W213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    Layer(7, "the bases aegis owns"'
assert s.count(old) == 1
p.write_text(s.replace(old, '    Layer(7, "the base images aegis owns"', 1))
P
}
# one more minute in an estimate is still an estimate
control_2() { python3 - "$W213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '          "revert the image: and sync", 25),'
assert s.count(old) == 1
p.write_text(s.replace(old, '          "revert the image: and sync", 26),', 1))
P
}
# a comment about the order of the layers is not the order
control_3() { printf '\n# note: the ground goes first and what stands on it after.\n' >> "$W213"; }

# the window stops asking which tools the phase downloads: a layer 2
# bump of an apt-managed tool is written, committed, and refused by the
# phase three commits later
red_11() { python3 - "$U213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    downloads = win.host_downloads()'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    downloads = None  # nobody asks the phase any more', 1))
P
}

# the reader of the phase comes back empty: the refusal never fires, and
# it looks exactly like a refusal that is working
red_12() { python3 - "$W213" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    for bm in re.finditer(r"^\\s{8}([a-z0-9|]+)\\)", m.group(1), re.M):'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    for bm in re.finditer(r"^\\s{8}([A-Z]+)\\)", m.group(1), re.M):', 1))
P
}
