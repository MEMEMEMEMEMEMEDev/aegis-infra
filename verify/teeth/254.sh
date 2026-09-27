# teeth of check 254 — a harmless call that speaks like the network.
B254="$AEGIS_ROOT/seed/platform/base-images/Jenkinsfile"
A254="$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# base-images' build event as it was on 2026-09-23: curl's error in the console (finding 13)
red_1() { _sub "$B254" "_msg_field=image&_stream_fields=source' 2>/dev/null \\
                  || echo \"NOTICE: the event could not be recorded in vlogs-events (curl exit \$?; the build does NOT fail for this)\"
                {" "_msg_field=image&_stream_fields=source' \\
                  || echo 'NOTICE: the event could not be recorded in vlogs-events (the build does NOT fail for this)'
                {"; }

# the tenant template's metrics call speaks again
red_2() { _sub "$A254" "'http://vmsingle.observability.svc.cluster.local:8428/api/v1/import/prometheus' 2>/dev/null \\" "'http://vmsingle.observability.svc.cluster.local:8428/api/v1/import/prometheus' \\"; }

# the notice itself names the network
red_3() { _sub "$B254" "NOTICE: the build metrics did not reach vmsingle (curl exit" "NOTICE: the build metrics did not reach vmsingle (could not resolve host? curl exit"; }

# the pod delete of the run step speaks again
red_4() { _sub "$B254" 'gracePeriodSeconds=0" 2>/dev/null || echo "NOTICE' 'gracePeriodSeconds=0" || echo "NOTICE'; }

# ── controls ──
# stderr discarded on the curl's first line instead of its last
control_1() { _sub "$A254" "            } | curl -fsS --max-time 15 --data-binary @- \\
                  'http://vmsingle.observability.svc.cluster.local:8428/api/v1/import/prometheus' 2>/dev/null \\" "            } | curl -fsS --max-time 15 --data-binary @- 2>/dev/null \\
                  'http://vmsingle.observability.svc.cluster.local:8428/api/v1/import/prometheus' \\"; }
# a NOTICE that is not a harmless call's (plain echo) is not in scope
control_2() { _sub "$B254" 'echo "NOTICE: nothing in ${REPO_SLUG} names' 'echo "NOTICE: could not resolve: nothing in ${REPO_SLUG} names'; }
