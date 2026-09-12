# teeth for check 099 (the console writes one contract or nothing)
#
# Every red is a change somebody would make to be helpful. None of them
# breaks the console: it goes on working, and the only difference is
# what it has already done by the time anybody notices.

C099="$AEGIS_ROOT/libexec/aegis-console"

# THE ONE. The console commits what it wrote — «so the operator does not
# have to». And with that, a file in a working tree stops being
# harmless: the next push is what ArgoCD reads.
red_1() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    with open(target, "w", encoding="utf-8") as fh:
        fh.write(text)
    return target, None'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    with open(target, "w", encoding="utf-8") as fh:
        fh.write(text)
    subprocess.run(["git", "-C", orgs, "commit", "-m", f"orgs: {name}"],
                   capture_output=True)
    return target, None''', 1))
P
}

# it writes over a contract that already exists: an edit arrives
# disguised as a create, and somebody loses an afternoon of decisions
red_2() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '    if os.path.exists(target):'
assert s.count(old) == 1
p.write_text(s.replace(old, '    if False:', 1))
P
}

# validated AFTER writing rather than before, so a contract the
# generator refuses is left sitting in the repository
red_3() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    bad = validate_contract(text)
    if bad:
        return None, bad'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''    bad = None''', 1))
P
}

# it applies too, «to save a step»: the manifests land in k8s/ and the
# next sync is somebody else's surprise
red_4() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    with open(target, "w", encoding="utf-8") as fh:
        fh.write(text)
    return target, None'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''    with open(target, "w", encoding="utf-8") as fh:
        fh.write(text)
    try:
        cli.run("org", "apply", target)
    except cli.CouldNotEvaluate:
        pass
    return target, None''', 1))
P
}

# it leaves a copy of every contract beside the real one, «for undo».
# Small, helpful, and a second place where a tenant's contract lives.
red_5() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    with open(target, "w", encoding="utf-8") as fh:
        fh.write(text)
    return target, None'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''    with open(target, "w", encoding="utf-8") as fh:
        fh.write(text)
    with open(target + ".anterior", "w", encoding="utf-8") as fh:
        fh.write(text)
    return target, None''', 1))
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the refusal's wording changes: it is for a person reading a screen
control_1() { sed -i 's/does not write over one that exists/never writes over one that exists/' "$C099"; }

# the console reads one more thing about itself, through git, that only
# looks: reading is not writing and the rule is about writing
control_2() { python3 - "$C099" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        return subprocess.run(["git", "-C", _AEGIS_ROOT, "rev-parse", "HEAD"],'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''        subprocess.run(["git", "-C", _AEGIS_ROOT, "status", "--short"],
                       capture_output=True, text=True)
        return subprocess.run(["git", "-C", _AEGIS_ROOT, "rev-parse", "HEAD"],''', 1))
P
}

# a comment recording why the write stops at the file
control_3() { printf '\n# note: ArgoCD reads the REMOTE. A contract in a working tree is a\n# proposal; what makes an organization exist is a commit.\n' >> "$C099"; }
