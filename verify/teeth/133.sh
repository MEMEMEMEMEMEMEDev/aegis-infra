# teeth for check 133 (nothing in the namespace goes unnamed)
#
# Every red makes the sweep walk past something. None of them looks like
# a bug in review: each one is the tidy version of the loop, and each one
# restores the exact state measured on this instance on 2026-09-12 — a
# hundred gigabytes with no copy and nothing saying so.

C133="$AEGIS_ROOT/libexec/aegis-tenant"

# THE ONE. The unclaimed volumes stop being swept. The screen goes back
# to showing only what the contract declares, which is the whole reason
# the gap was invisible for nine days.
red_1() { python3 - "$C133" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    if volumes is not None:
        for v in volumes:
            name = v["metadata"]["name"]
            if name in claimed:
                continue'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    if False:
        for v in volumes:
            name = v["metadata"]["name"]
            if name in claimed:
                continue''', 1))
P
}

# the tidy version: only claims that carry an `app` label are swept.
# Reasonable-looking, and it walks past precisely the one that was
# created outside the generator — which is the only kind at risk.
red_2() { python3 - "$C133" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            if name in claimed:
                continue'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''            if name in claimed or not ((v.get("metadata") or {}).get("labels") or {}).get("app"):
                continue''', 1))
P
}

# the workload nobody declared stops being named: an old Deployment
# left behind by a rename keeps running, eating the quota, and the
# organization's screen looks exactly as its contract promised
red_3() { python3 - "$C133" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    for app, w in sorted(live.items()):'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''    for app, w in sorted({}.items()):''', 1))
P
}

# it is named and filed as fine. Naming a thing and then saying it is in
# order is worse than silence: the reader is told and reassured at once
red_4() { python3 - "$C133" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''            steps.wrong(f"unclaimed-volume:{name}", size=size,'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''            steps.already(f"unclaimed-volume:{name}", size=size,''', 1))
P
}

# the other half: everything becomes a stranger. A sweep that calls the
# declared service unclaimed would pass a check that only counted
# findings, and it would make the screen useless in the other direction
red_5() { python3 - "$C133" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        w = live.pop(app, None)'
assert s.count(old) == 1
p.write_text(s.replace(old, '        w = live.get(app, None)', 1))
P
}

# ── controls: real changes that must NOT move the verdict ────────────

# the sentence the operator reads changes: no check reads prose
control_1() { sed -i 's/and no service of the contract declares it/and no service of this contract declares it/' "$C133"; }

# more is reported about a stranger: growing the record is not deciding
control_2() { python3 - "$C133" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        steps.wrong(f"unclaimed:{w['name']}", kind=w["kind"], ready=w["ready"],'''
assert s.count(old) == 1
p.write_text(s.replace(old, '''        steps.wrong(f"unclaimed:{w['name']}", namespace=ns, kind=w["kind"], ready=w["ready"],''', 1))
P
}

# a comment recording where the rule came from
control_3() { printf '\n# note: the contract is what every tool here derives from, so anything\n# the contract does not name is invisible to all of them at once.\n' >> "$C133"; }
