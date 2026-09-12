# teeth for check 121 (blind is not an empty organization)
#
# Every red makes the command answer a question nobody asked it. None
# of them crashes, none prints a traceback: the document comes out
# well-formed and says something false about a real organization.

C121="$AEGIS_ROOT/libexec/aegis-tenant"

# THE ONE. The apiserver is silent and the command carries on with an
# empty namespace — so every declared service comes out absent, which on
# a screen is the sentence «nothing of this organization is running».
red_1() { python3 - "$C121" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            steps.not_evaluable(f"tenant:{org}", why="apiserver-silent", detail=detail)
            steps.finish()'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''            pass''', 1))
P
}

# the state is right and the rc is not. rc 2 is the only value that
# means «nobody asked», and everything downstream reads the number
red_2() { python3 - "$C121" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '            steps.not_evaluable(f"tenant:{org}", why="apiserver-silent", detail=detail)'
assert s.count(old) == 1
p.write_text(s.replace(old, '            steps.wrong(f"tenant:{org}", why="apiserver-silent", detail=detail)', 1))
P
}

# the other direction, and the quieter one: a namespace that really is
# gone gets filed as «I could not look». A red gets investigated; an
# «I do not know» never does.
red_3() { python3 - "$C121" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        steps.wrong("namespace", namespace=ns, exists=False)'
assert s.count(old) == 1
p.write_text(s.replace(old, '        steps.not_evaluable("namespace", namespace=ns, exists=False)', 1))
P
}

# an absent namespace stops naming the services: the screen says «this
# organization is not there» and cannot show the shape of what is gone
red_4() { python3 - "$C121" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        for sv in services:
            steps.wrong(f"service:{sv['nombre']}", tipo=sv["tipo"],
                        why="no-namespace", ready=0, desired=None)'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''        for sv in []:
            pass''', 1))
P
}

# «NotFound» stops being read as an answer, so a missing namespace and a
# dead kubeconfig become the same thing — the exact pair this check exists
# to keep apart, collapsed from the other side
red_5() { python3 - "$C121" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        if "NotFound" not in detail and "not found" not in detail:'
assert s.count(old) == 1
p.write_text(s.replace(old, '        if True:', 1))
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the narration changes: it is for people, and no check reads it
control_1() { sed -i 's/this is not an organization that is down/this is not an organization that has been switched off/' "$C121"; }

# a fact is added to a measured step: reporting more is not deciding more
control_2() { sed -i 's/steps.already("namespace", namespace=ns, exists=True, phase=phase)/steps.already("namespace", namespace=ns, exists=True, phase=phase, measured=True)/' "$C121"; }

# a comment that names the three answers: the rule is about what the
# command does, not about the words appearing in the file
control_3() { printf '\n# note: blind, absent and healthy are three answers and three rc — 2, 1\n# and 0. A screen that folds the first two sends somebody to rebuild an\n# organization that was serving traffic.\n' >> "$C121"; }
