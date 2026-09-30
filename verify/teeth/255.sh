# teeth of check 255 — one verdict decides what a known vulnerability costs.
V255="$AEGIS_ROOT/seed/platform/k8s/base/platform/vuln-policy/verdict.sh"
K255="$AEGIS_ROOT/seed/platform/k8s/base/platform/vuln-policy/kustomization.yaml"
J255="$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins-secrets/kustomization.yaml"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the gate as it was until 2026-09-30: every finding is the change's, what already runs stops the build
red_1() { _sub "$V255" 'if (mode == "change" && !(($1 "|" $3 "|" $7) in RUNS)) {' 'if (mode == "change") {'; }

# the other way round: a change that brings a finding passes as if it had been running
red_2() { _sub "$V255" 'if (mode == "change" && !(($1 "|" $3 "|" $7) in RUNS)) {' 'if (mode == "change" && 0) {'; }

# an exploited-in-the-wild finding gets a window like any other
red_3() { _sub "$V255" '    if (kev) { say("block", "exploited in the wild: no window"); next }
' ''; }

# an old exploited-in-the-wild list is trusted to say «not exploited»
red_4() { _sub "$V255" '            else kevknown = 1' '            kevknown = 1'; }

# a finding with no publication date is dated today, and gets a window it cannot have
red_5() { _sub "$V255" 'pub = dfc($6); due = "?"' 'pub = ($6 == "" ? t : dfc($6)); due = "?"'; }

# a malformed line is skipped: an unjudged scan reads as judged
red_6() { _sub "$V255" 'NF != 9 { print "verdict: malformed finding line (9 fields expected): " $0 > "/dev/stderr"; bad = 1; exit 3 }' 'NF != 9 { next }'; }

# the window stops being the policy's: the high one takes the critical's number
red_7() { _sub "$V255" 'days["HIGH"] = P["high_days"]' 'days["HIGH"] = P["critical_days"]'; }

# the ConfigMap stops carrying the verdict to the tenants' agents
red_8() { _sub "$K255" '      - verdict.sh
' ''; }

# the ConfigMap is generated and never lands in jenkins-system
red_9() { _sub "$J255" '  - ../vuln-policy ' '  # - ../vuln-policy '; }

# ── controls ──
# the reasons are words: rewording one changes no verdict
control_1() { _sub "$V255" '"already running, past its window"' '"already running, and its window has closed"'; }
# the policy's keys in another order read the same numbers
control_2() { python3 - "$AEGIS_ROOT/seed/platform/k8s/base/platform/vuln-policy/policy.yaml" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
a, b = "critical_days: 15\n", "high_days: 30\n"
assert s.count(a + b) == 1, "re-aim this control"
p.write_text(s.replace(a + b, b + a, 1))
PY
}
