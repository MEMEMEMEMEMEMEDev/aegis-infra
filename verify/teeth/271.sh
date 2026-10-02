# teeth of check 271 — the alerts climb the books' ladder.
R271="$AEGIS_ROOT/seed/platform/k8s/base/observability/rules/vmalert-rules.yaml"
A271="$AEGIS_ROOT/seed/platform/k8s/base/observability/alertmanager.yaml"
L271="$AEGIS_ROOT/seed/platform/image-watch/ledger.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the overdue rung reads the wrong state: it never fires
red_1() { _sub "$R271" 'aegis_vuln_findings{state="overdue"}[2d]' 'aegis_vuln_findings{state="past_due"}[2d]'; }

# the exploited rung waits an hour
red_2() { _sub "$R271" '            expr: sum by (image) (last_over_time(aegis_vuln_findings{state="exploited"}[2d])) > 0
            labels: {severity: critical}' '            expr: sum by (image) (last_over_time(aegis_vuln_findings{state="exploited"}[2d])) > 0
            for: 1h
            labels: {severity: critical}'; }

# debt pages like an outage: the daily route is gone
red_3() { _sub "$A271" '          repeat_interval: 24h
' '          repeat_interval: 12h
'; }

# the ledger stops emitting due_soon: the warning rung can never fire
red_4() { _sub "$L271" 'split("debt due_soon overdue exploited", st, " ")' 'split("debt overdue exploited", st, " ")'; }

# the overdue rung is a mere warning
red_5() { _sub "$R271" '              summary: "{{ $labels.image }}: {{ $value }} known vulnerability(ies) PAST their due date"' '              summary: "{{ $labels.image }}: {{ $value }} known vulnerability(ies) PAST their due date"
            labels: {severity: warning}'; }

# ── controls ──
control_1() { _sub "$R271" 'Fix it first, before anything else.' 'Fix it before anything else.'; }
