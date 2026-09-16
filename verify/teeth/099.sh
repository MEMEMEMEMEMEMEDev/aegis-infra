# teeth for check 099 (the console writes one contract or nothing)
#
# Every red is a change somebody would make to be helpful. None of them
# breaks the console: it goes on working, and the only difference is
# what it has already done by the time anybody notices.
#
# THE TWO WRITE DOORS END IDENTICALLY — a create and an overwrite both
# finish by writing the file — so a tooth aimed at that ending has to
# say WHICH one it means. Four of these broke silently on 2026-09-13
# when `replace_contract` was added and nothing said so until the teeth
# were run again: a tooth that cannot be applied is not a tooth that
# bites, and it is quiet about it. They are anchored on what FOLLOWS
# `write_contract` now, which belongs to it alone.

C099="$AEGIS_ROOT/libexec/aegis-console"

# THE ONE. The console commits what it wrote — «so the operator does not
# have to». And with that, a file in a working tree stops being
# harmless: the next push is what ArgoCD reads.
red_1() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = "    return target, None\n\n\ndef read_contract(org):"
assert s.count(old) == 1, "re-aim this tooth"
new = ('    subprocess.run(["git", "-C", orgs, "commit", "-m", f"orgs: {name}"],\n'
       '                   capture_output=True)\n'
       '    return target, None\n\n\ndef read_contract(org):')
p.write_text(s.replace(old, new, 1))
P
}

# it writes over a contract that already exists: an edit arrives
# disguised as a create, and somebody loses an afternoon of decisions
red_2() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = "    if os.path.exists(target):"
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, "    if False:", 1))
P
}

# validated AFTER writing rather than before, so a contract the
# generator refuses is left sitting in the repository. The create door
# is the first of the two that validate.
red_3() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = "    bad = validate_contract(text)\n    if bad:\n        return None, bad"
assert s.count(old) == 2, "both doors validate first: this aims at the create one"
p.write_text(s.replace(old, "    bad = None", 1))
P
}

# it applies too, «to save a step»: the manifests land in k8s/ by a path
# nobody agreed to, and the next sync is somebody else's surprise
red_4() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = "    return target, None\n\n\ndef read_contract(org):"
assert s.count(old) == 1, "re-aim this tooth"
new = ('    try:\n'
       '        cli.run_json("org", "delete", target)\n'
       '    except cli.CouldNotEvaluate:\n'
       '        pass\n'
       '    return target, None\n\n\ndef read_contract(org):')
p.write_text(s.replace(old, new, 1))
P
}

# it leaves a copy of every contract beside the real one, «for undo».
# Small, helpful, and a second place where a tenant's contract lives.
red_5() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = "    return target, None\n\n\ndef read_contract(org):"
assert s.count(old) == 1, "re-aim this tooth"
new = ('    with open(target + ".anterior", "w", encoding="utf-8") as fh:\n'
       '        fh.write(text)\n'
       '    return target, None\n\n\ndef read_contract(org):')
p.write_text(s.replace(old, new, 1))
P
}

# ── the errand (2026-09-14) ──────────────────────────────────────────

# THE HOLE THAT WAS OPEN. A call built out of variables hands the AST
# nothing to read, so the console could invoke anything at all and the
# list of literal invocations would stay empty. The blunt half is what
# catches it: a console that never spells the word cannot do the thing.
red_6() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '("org", ("apply", path), "manifests")'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '("org", ("delete", path), "manifests")', 1))
P
}

# the console stops deriving the manifests, so whoever used the screen
# has a contract and an organization missing six files, and nothing told
# them
red_7() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '("org", ("apply", path), "manifests")'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '("org", ("validate", path), "manifests")', 1))
P
}

# it derives MORE than the errand: a file the CLI's own path does not
# leave behind, which makes the console a second way of producing a
# platform repository
red_8() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = "    done = []\n    for verb, args, what in"
assert s.count(old) == 1, "re-aim this tooth"
new = ('    done = []\n'
       '    with open(path + ".consola", "w", encoding="utf-8") as fh:\n'
       '        fh.write("written by the console\\n")\n'
       '    for verb, args, what in')
p.write_text(s.replace(old, new, 1))
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the refusal's wording changes: it is for a person reading a screen
control_1() { sed -i 's/does not write over one that exists/never writes over one that exists/' "$C099"; }

# the console reads one more thing about itself through git, and it only
# LOOKS: reading is not writing, and the rule is about writing
control_2() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        return subprocess.run(["git", "-C", _AEGIS_ROOT, "rev-parse", "HEAD"],'
assert s.count(old) == 1
new = ('        subprocess.run(["git", "-C", _AEGIS_ROOT, "status", "--short"],\n'
       '                       capture_output=True, text=True)\n'
       '        return subprocess.run(["git", "-C", _AEGIS_ROOT, "rev-parse", "HEAD"],')
p.write_text(s.replace(old, new, 1))
P
}

# a comment recording why the write stops at the file
control_3() { printf '\n# note: ArgoCD reads the REMOTE. A contract in a working tree is a\n# proposal; what makes an organization exist is a commit.\n' >> "$C099"; }

# the two commands that write files in this instance are legitimate, and
# renaming what the screen calls them is not naming a change outside it
control_4() { sed -i 's/("secret", ("create", path), "secrets")/("secret", ("create", path), "the secrets")/' "$C099"; }

# the console adds a plan and changes one; it never REMOVES one. The
# screen that changes a plan starts invoking `quota remove` — which is
# `aegis quota` by hand, reading what it says — and the policy refuses.
red_9() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'cli.run_json("quota", "set", plan.get("nombre") or "", *_plan_args(plan))'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, 'cli.run_json("quota", "remove", plan.get("nombre") or "", *_plan_args(plan))', 1))
P
}

# reading the catalogue once more is reading, wherever it is done from
control_5() { printf '\n\ndef _plans_again():\n    return cli.run_json("quota", "list")[1]\n' >> "$C099"; }
