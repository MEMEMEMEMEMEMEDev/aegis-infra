# teeth for check 201 (an edit changes what you changed)
#
# Every red is the state this screen was actually in while it was being
# written, or one keystroke away from it. None of them fails: the plan
# looks tidy, the page says it saved, and the loss shows up days later
# in somebody else's namespace.

C201="$AEGIS_ROOT/lib/aegis/console.py"
S201="$AEGIS_ROOT/libexec/aegis-console"

# THE ONE. The contract is rebuilt from the form instead of changed.
# `usa`, the storage block and the ai tasks all disappear, and `usa`
# being optional means nothing refuses it.
red_1() { python3 - "$C201" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    current = current or {}
    contract = copy.deepcopy(current)'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    current = current or {}
    contract = {"version": (current or {}).get("version", 1)}''', 1))
P
}

# only the services are rebuilt: the top level survives and every `usa`
# in the contract is gone. Smaller, and exactly as quiet.
red_2() { python3 - "$C201" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        base = copy.deepcopy(services[i]) if i < len(services) else {}'
assert s.count(old) == 1
p.write_text(s.replace(old, '        base = {}', 1))
P
}

# a service that the form did not reach stops being carried over: an
# organization with more services than the form has rows loses the tail
red_3() { python3 - "$C201" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    for j in range(i, len(services)):
        out.append(copy.deepcopy(services[j]))'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''    for j in []:
        out.append(copy.deepcopy(services[j]))''', 1))
P
}

# the refusals stop being consulted: dropping a service and renaming the
# organization both go through
red_4() { python3 - "$C201" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    refused = refuse_edit(contract, current)
    if refused:
        return None, None, refused'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''    refused = None''', 1))
P
}

# the two doors become one: the edit door creates what is not there, so
# a create arrives disguised as an edit and skips every question the
# create screen asks
red_5() { python3 - "$S201" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    if not os.path.exists(target):
        return None, (f"there is no contract at {target} to change.'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''    if False:
        return None, (f"there is no contract at {target} to change.''', 1))
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the refusal's wording changes: it is for a person reading a screen
control_1() { sed -i 's/second contract and leave the first one where it is/second contract and leave the first one exactly where it is/' "$C201"; }

# one more field becomes editable from the form. Growing what the screen
# shows is not changing what it preserves.
control_2() { python3 - "$C201" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'SHOWN = ("nombre", "tipo", "puerto", "publico", "repo", "tamano")'
assert s.count(old) == 1
p.write_text(s.replace(old, 'SHOWN = ("nombre", "tipo", "puerto", "publico", "repo", "tamano", "rama")', 1))
P
}

# a comment recording where the rule came from
control_3() { printf '\n# note: the form shows six fields per service and a contract carries\n# more. Anything this screen does not display comes out the other side\n# exactly as it went in, because nothing would refuse its loss.\n' >> "$C201"; }
