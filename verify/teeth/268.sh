# teeth of check 268 — aegis vulns and the round read the books.
V268="$AEGIS_ROOT/libexec/aegis-vulns"
C268="$AEGIS_ROOT/libexec/aegis-check"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the books are read from the clone, not from the remote the watch commits to
red_1() { _sub "$V268" '    ref = r.stdout.strip() if r.returncode == 0 else "HEAD"' '    ref = "HEAD"'; }

# nobody fetches: the remote-tracking ref says what the clone already knew
red_2() { _sub "$V268" '    f = subprocess.run(["git", "-C", str(platform), "fetch", "--quiet"],' '    f = subprocess.run(["git", "-C", str(platform), "status", "--short"],'; }

# debt inside its window is a failure again: every round red over what the policy accepted
red_3() { _sub "$V268" '        if n["exploited"] or n["overdue"]:' '        if True:'; }

# a silent watch's books read as today's
red_4() { _sub "$V268" '        if age_h > SILENT_AFTER_H:' '        if False:'; }

# an image the watch could not scan reads as nothing owed
red_5() { _sub "$V268" '        if "unmeasured" in states:' '        if False:'; }

# the round turns an overdue image into a notice
red_6() { _sub "$C268" '            print(f"BAD|{img}: " + ", ".join(parts))' '            print(f"NOTICE|{img}: " + ", ".join(parts))'; }

# the round turns debt inside its window into a failure
red_7() { _sub "$C268" '            print(f"NOTICE|{img}: {len(found)} known vulnerability(ies) inside the window, the next due {nxt}"' '            print(f"BAD|{img}: {len(found)} known vulnerability(ies) inside the window, the next due {nxt}"'; }

# the heartbeat is looked for at the clusterIP alone: vmsingle is headless, and it is never found
red_8() { _sub "$V268" '    where = window.service_endpoint("observability", "vmsingle")' '    where = None if window._kubectl("get", "svc", "-n", "observability", "vmsingle", "-o", "jsonpath={.spec.clusterIP}")[1] in ("", "None") else window.service_endpoint("observability", "vmsingle")'; }

# ── controls ──
control_1() { _sub "$V268" '"EXPLOITED in the wild: it has no window"' '"EXPLOITED in the wild: no window applies"'; }
control_2() { _sub "$C268" "who fixes it: {s.get('fixer', '?')}" "fixed by: {s.get('fixer', '?')}"; }
