# teeth for 222 — each red brings back the way a bump reached git,
# reported itself raised, and never reached the cluster.
U222="$AEGIS_ROOT/libexec/aegis-update"
W222="$AEGIS_ROOT/lib/aegis/window.py"

# the chart layer goes back to syncing only the app: the Application
# object keeps naming the old version and everything reports green
red_1() { python3 - "$U222" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        appliers = win.appliers_of(wrote["ficheros"])'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '        appliers = []', 1))
P
}

# the version is never read back: Synced+Healthy is taken as an answer
# about the version
red_2() { python3 - "$U222" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        live = win.live_chart_version(app)'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '        live = bump["a"]', 1))
P
}

# the version is read back, but after the chart has been counted as
# raised — a note, not a check
red_3() { python3 - "$U222" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''        live = win.live_chart_version(app)'''
assert s.count(old) == 1, "re-aim this tooth"
i = s.index(old)
j = s.index('        done.append(app)', i)
bloque = s[i:j]
s = s[:i] + s[j:]
s = s.replace('        done.append(app)\n', '        done.append(app)\n' + bloque, 1)
p.write_text(s)
P
}

# the applier is matched on characters: an app whose source is
# `k8s/base` claims `k8s/base-images/alpine/Containerfile`
red_4() { python3 - "$W222" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '                if f == path or f.startswith(path + "/"):'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '                if f.startswith(path):', 1))
P
}

# a kubectl that cannot answer becomes «nobody applies this», so the
# bump is never routed and the layer carries on
red_5() { python3 - "$W222" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    rc, out, _ = _kubectl("get", "applications", "-n", "argocd", "-o", "json")
    if rc != 0:
        return None'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    rc, out, _ = _kubectl("get", "applications", "-n", "argocd", "-o", "json")
    if rc != 0:
        return []''', 1))
P
}

# a version that could not be read becomes a version: the layer compares
# the bump against a guess and always agrees with itself
red_6() { python3 - "$W222" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    rc, out, _ = _kubectl(
        "get", "application", app, "-n", "argocd", "-o",
        "jsonpath={range .spec.sources[*]}{.chart}|{.targetRevision}{\\"\\\\n\\"}{end}")
    if rc != 0:
        return None'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, old.replace("        return None", '        return "unknown"'), 1))
P
}

# a chart Application with several sources stops being readable: every
# chart app here has that shape, so the read-back answers None forever
red_7() { python3 - "$W222" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '''    for ln in out.splitlines():
        chart, _, rev = ln.partition("|")
        if chart.strip():
            return rev.strip()'''
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''    for ln in []:
        chart, _, rev = ln.partition("|")
        if chart.strip():
            return rev.strip()''', 1))
P
}

# ── controls ──
# the wording of the refusal is prose
control_1() { sed -i 's/nobody could be asked who applies this file/nobody could be asked who applies this path/' "$U222"; }
# a comment naming the mistake is not the fix
control_2() { printf '\n# note: targetRevision lives in the Application object, not in its contents.\n' >> "$W222"; }
# syncing the applier twice is still syncing the applier
control_3() { python3 - "$U222" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        appliers = win.appliers_of(wrote["ficheros"])'
p.write_text(s.replace(old, old + '\n        appliers = list(appliers or []) or appliers', 1))
P
}
