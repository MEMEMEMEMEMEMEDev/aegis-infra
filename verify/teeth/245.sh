# teeth of check 245 — a release does not drop the people on the site.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
CAN245="$AEGIS_ROOT/seed/canary/k8s/base/deployment.yaml"
PY245="$AEGIS_ROOT/seed/templates/service-python/repos/app/k8s/base/deployment.yaml"

# the canary as it was on 2026-09-24: no preStop at all
red_1() { _sub "$CAN245" '          lifecycle:
            preStop:
              sleep: {seconds: 5}
' ''; }

# a template loses it
red_2() { _sub "$PY245" '          lifecycle:
            preStop:
              sleep: {seconds: 5}
' ''; }

# a wait shorter than the propagation measured
red_3() { _sub "$CAN245" 'sleep: {seconds: 5}' 'sleep: {seconds: 1}'; }

# the grace period shorter than the wait: the kill lands first
red_4() { _sub "$PY245" '      terminationGracePeriodSeconds: 30' '      terminationGracePeriodSeconds: 4'; }

# control: the same wait, written in block style
control_1() { _sub "$CAN245" '              sleep: {seconds: 5}' '              sleep:
                seconds: 5'; }
