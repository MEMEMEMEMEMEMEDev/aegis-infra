# teeth for 204 — `aegis quota` must refuse what is not a plan and leave
# the file as it found it. Each red removes ONE refusal or one care.
Q204="$AEGIS_ROOT/libexec/aegis-quota"

# a ceiling under its floor becomes a plan
red_1() { python3 - "$Q204" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    if quantity.cpu(numbers["limits.cpu"]) < quantity.cpu(numbers["requests.cpu"]):'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    if False:', 1))
P
}

# the shipped plans' numbers can be changed on this instance
red_2() { python3 - "$Q204" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    if sets and name in shipped():'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    if False:', 1))
P
}

# a plan a contract names can be removed
red_3() { python3 - "$Q204" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    who = users().get(name, [])
    if who:
        steps.wrong('''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    who = users().get(name, [])
    if False:
        steps.wrong(''', 1))
P
}

# a shipped plan can be removed
red_4() { python3 - "$Q204" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    if name in shipped():
        steps.wrong(f"plan:{name}", error=f"{name!r} is a plan aegis ships, and it stays.")'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    if False:
        steps.wrong(f"plan:{name}", error=f"{name!r} is a plan aegis ships, and it stays.")''', 1))
P
}

# removing leaves the blank lines behind: add and remove no longer round-trips
red_5() { python3 - "$Q204" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    new[i:j] = ["\\n"] if 0 < i < len(new) else []'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    pass', 1))
P
}

# a name that exists is written again
red_6() { python3 - "$Q204" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    if name in cuota:\n        steps.wrong(f"plan:{name}", error=f"there is already a plan named {name!r}. Changing "'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '    if False:\n        steps.wrong(f"plan:{name}", error=f"there is already a plan named {name!r}. Changing "', 1))
P
}

# ── controls ──
# the sentence of a refusal is reworded: words are not the rule
control_1() { sed -i 's/a ceiling under the floor is not a plan\./a ceiling below the floor is not a plan./' "$Q204"; }
# a comment is added
control_2() { printf '\n# note: plans.yaml is edited textually so that its margins survive.\n' >> "$Q204"; }
# the comment a new block carries is reworded
control_3() { sed -i 's/Yours to\\n/Yours, to\\n/' "$Q204"; }
