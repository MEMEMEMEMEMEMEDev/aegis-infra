# teeth of check 264 — app apply plants the skeleton last; app new's steps in order.
A264="$AEGIS_ROOT/libexec/aegis-app"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# apply as it was on 2026-09-30: the skeleton before the webhook
red_1() { python3 - "$A264" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
a = """    apply_webhooks(write, tot)
    # LAST: every hook exists by now, so each skeleton's push reaches
    # Jenkins and is the app's first build.
    for r in to_plant:
        plant_skeleton(r, write, tot)
"""
b = """    for r in to_plant:
        plant_skeleton(r, write, tot)
    apply_webhooks(write, tot)
"""
assert s.count(a) == 1, "re-aim"
p.write_text(s.replace(a, b, 1))
PY
}

# app new's steps as they were: apply --check before the push
red_2() { python3 - "$A264" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
a = s[s.index('    print(f"  2. commit+push of platform/'):s.index('    print(f"  4. {cli.cmd(\'app apply\')}')]
b = s[s.index('    print(f"  4. {cli.cmd(\'app apply\')}'):s.index("          f\"{gray}(repo, deploy key, webhook")]
assert a and b
s = s.replace(a + b, b + a, 1)
p.write_text(s)
PY
}

# ── controls ──
control_1() { _sub "$A264" '(skeleton — its push is the first build)' '(skeleton: its push is the first build)'; }
