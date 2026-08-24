# teeth for check 109 (no stage writes into an absent subsystem)
#
# The correct mutation is the REGRESSION, not something like it: take
# the guard off the stage and leave it as it was on 2026-08-24, when
# `aegis org apply` died with FileNotFoundError after having written
# six manifests.
red_1() {
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('def apply_routes(write):\n'
              '    rc = _without_ai_subsystem("routes")\n'
              '    if rc is not None:\n'
              '        return rc\n',
              'def apply_routes(write):\n')
open(p, "w").write(s)
PY
}

# the other stage, because there are two and the check has to see both
red_2() {
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('def apply_ai_registry(write):\n'
              '    rc = _without_ai_subsystem("AI registry")\n'
              '    if rc is not None:\n'
              '        return rc\n',
              'def apply_ai_registry(write):\n')
open(p, "w").write(s)
PY
}

# a NEW stage that writes blind into a subsystem that is not there: the
# check has to bite whatever comes, not only the two it already knows.
# That is the difference between watching the class and watching the case.
red_3() {
    cat >> "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'


FUTURE_K8S = os.path.join(PLATFORM_ROOT, "k8s", "base", "future-subsystem", "something.yaml")


def apply_future(write):
    if write:
        open(FUTURE_K8S, "w", encoding="utf-8").write("x")
    return 0
PY
}

# control: a new stage that writes where the artifact DOES have a
# folder needs no guard at all, and turning red on that would be biting
# too much.
control_1() {
    cat >> "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'


LEGITIMATE_K8S = os.path.join(PLATFORM_ROOT, "k8s", "bootstrap", "legitimate.yaml")


def apply_legitimate(write):
    if write:
        open(LEGITIMATE_K8S, "w", encoding="utf-8").write("x")
    return 0
PY
}
