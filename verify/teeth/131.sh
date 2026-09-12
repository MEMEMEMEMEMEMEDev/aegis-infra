# teeth for check 131 (blind is not full)
#
# Every red turns «I could not look» into a number. None of them fails:
# the command exits, the console draws a figure, and somebody decides
# not to create an organization because of a machine nobody asked.

C131="$AEGIS_ROOT/libexec/aegis-capacity"

# THE ONE. The apiserver does not answer and the command carries on with
# zeros — which reads, on a screen, exactly like a full machine.
red_1() { python3 - "$C131" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        steps.not_evaluable("capacity", why="apiserver-silent", detail=str(e))
        steps.finish()'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        names, alloc_cpu, alloc_mem = ["unknown"], 0, 0
        pods, used_cpu, used_mem = 0, 0, 0''', 1))
P
}

# the state is right and the rc is not: the round and the console both
# read that number, and 0 means «measured and fine»
red_2() { python3 - "$C131" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        steps.not_evaluable("capacity", why="apiserver-silent", detail=str(e))'
assert s.count(old) == 1
p.write_text(s.replace(old, '        steps.already("capacity", why="apiserver-silent")', 1))
P
}

# the numbers come home: somebody writes what a plan costs into the
# command, and it keeps answering after plans.yaml moves
red_3() { python3 - "$C131" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        plans = (yaml.safe_load(open(PLANS, encoding="utf-8")) or {}).get("cuota") or {}'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''        plans = {"pequena": {"requests.cpu": "2", "requests.memory": "2Gi"}}''', 1))
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the prose of the report changes: it is for people
control_1() { sed -i 's/and one more organization of each plan:/room for one more of each plan:/' "$C131"; }

# a fact is added to every step: growing what is reported is not
# deciding anything about it
control_2() { sed -i 's/steps.already("capacity:nodes", nodes=len(names), pods=pods)/steps.already("capacity:nodes", nodes=len(names), pods=pods, measured=True)/' "$C131"; }

# prose that names a plan, in a comment: the rule is about the code
# deciding, not about the word appearing
control_3() { printf '\n# note: what a `pequena` asks for is NOT written here — plans.yaml says\n# it, and it is readjusted for every organization at once.\n' >> "$C131"; }
