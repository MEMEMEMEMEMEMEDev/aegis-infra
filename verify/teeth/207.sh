# teeth for 207 — the way back has to come all the way back. Each red is
# a way a rollback has failed in a real system, applied to the machinery
# the window actually calls.
W207="$AEGIS_ROOT/lib/aegis/window.py"

# reverted oldest first: two bumps of the same pin no longer apply
red_1() { python3 - "$W207" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    for entry in reversed(journal.commits()):'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    for entry in journal.commits():', 1))
P
}

# the commit stages the whole tree: somebody else's work rides in, and
# the rollback reverts it
red_2() { python3 - "$W207" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    git(root, "add", "--", *rel)
    rc, out, err = git(root, "commit", "-m", subject, "--", *rel, check=False)'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    git(root, "add", "-A")
    rc, out, err = git(root, "commit", "-m", subject, check=False)''', 1))
P
}

# a conflict is swallowed: the walk goes past it and reports success
# about a tree nobody described
red_3() { python3 - "$W207" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        git(root, "revert", "--abort", check=False)
        raise GitTrouble(f"the commit {sha[:12]} does not revert cleanly "
                         f"({(err or out).strip()[:200]}) — the tree was left as it was")'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        git(root, "revert", "--abort", check=False)
        return head(root)''', 1))
P
}

# the way back says «the same» by comparing the commit instead of the
# content: after a rollback the commit is necessarily a different one
red_4() { python3 - "$W207" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    want = before.get("tree")'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    want = before.get("head")''', 1))
P
}

# an edit into a line that does not read as the inventory said is
# written anyway, instead of refused
red_5() { python3 - "$W207" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            if pin.current not in new:
                raise RefusedEdit('''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''            if False:
                raise RefusedEdit(''', 1))
P
}

# ── controls ──
# a comment about the way back is not the way back
control_1() { printf '\n# note: a window is allowed to change things because it can undo them.\n' >> "$W207"; }
# the wording of a refusal changes; what it refuses does not
control_2() { python3 - "$W207" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'f"{pin.key}: an edit was asked for that changes nothing"'
assert s.count(old) == 1
p.write_text(s.replace(old, 'f"{pin.key}: this edit would change nothing at all"', 1))
P
}
# one more thing written into the journal changes nothing about the walk
control_3() { python3 - "$W207" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        done.append({"sha": sha, "subject": entry.get("subject", ""), "revert": new})'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''        done.append({"sha": sha, "subject": entry.get("subject", ""), "revert": new,
                     "orden": len(done) + 1})''', 1))
P
}
