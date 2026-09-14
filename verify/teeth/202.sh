# teeth for check 202 (a silent account is not an empty one)
#
# Every red turns a question nobody could ask into an answer. None of
# them fails: the command exits 0, the screen draws a tidy list, and the
# list is about an account nobody reached.

C202="$AEGIS_ROOT/libexec/aegis-repos"

# THE ONE. `gh` does not answer and the command carries on with an empty
# list — which on a screen is «you have no repositories».
red_1() { python3 - "$C202" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        steps.not_evaluable("repos", why="gh-silent",
                            detail=why[0][:200] if why else "gh did not answer")
        steps.finish()'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        repos = []
        r.stdout = "[]"''', 1))
P
}

# the state is right and the rc is not. rc 2 is the only value that
# means «nobody asked», and everything downstream reads the number.
red_2() { python3 - "$C202" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        steps.not_evaluable("repos", why="gh-silent",'
assert s.count(old) == 1
p.write_text(s.replace(old, '        steps.already("repos", why="gh-silent",', 1))
P
}

# the failure stops being noticed AT EITHER END. The command guards it
# twice —a non-zero exit, and an answer that does not parse— and the two
# are one idea written in two places, so this removes both: whatever
# `gh` did, the list comes back empty and the screen says the account
# has nothing in it.
red_3() { python3 - "$C202" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
a = "    if r.returncode != 0:"
b = ('        steps.not_evaluable("repos", why="unreadable-answer", detail=str(e))\n'
     "        steps.finish()")
assert s.count(a) == 1 and s.count(b) == 1, "re-aim this tooth"
s = s.replace(a, "    if False:", 1)
s = s.replace(b, "        repos = []", 1)
p.write_text(s)
P
}


# one tree, two services, and only the last one survives: a front and a
# bff out of the same repository, and the screen shows one of them
red_4() { python3 - "$C202" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''                out.setdefault(name, []).append({"organizacion": org,'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''                out[name] = []
                out[name].append({"organizacion": org,''', 1))
P
}

# a repository nothing claims is painted as a finding. On the one screen
# where a colour has to mean something, thirty amber rows teach the
# reader to stop looking.
red_5() { python3 - "$C202" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        steps.already(f"repo:{x[\'name\']}", **data)'
assert s.count(old) == 1
p.write_text(s.replace(old, '''        (steps.already if uses else steps.wrong)(f"repo:{x['name']}", **data)''', 1))
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the narration changes: it is for people, and no check reads it
control_1() { sed -i 's/it is one nobody could look at/it is one that nobody was able to look at/' "$C202"; }

# one more field is carried about each repository: reporting more is not
# deciding anything different
control_2() { python3 - "$C202" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '                "empujado": x.get("pushedAt"), "url": x.get("url"),'
assert s.count(old) == 1
new = ('                "empujado": x.get("pushedAt"), "url": x.get("url"),\n'
       '                "descrito": True,')
p.write_text(s.replace(old, new, 1))
P
}

# a comment recording why an empty list is not an answer
control_3() { printf '\n# note: GitHub is behind a network, a token and a rate limit. Any of the\n# three can be the reason an answer does not arrive, and none of them\n# means the account is empty.\n' >> "$C202"; }
