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
s = s.replace('def aplicar_ruteo(escribir):\n'
              '    rc = _sin_subsistema_ai("ruteo")\n'
              '    if rc is not None:\n'
              '        return rc\n',
              'def aplicar_ruteo(escribir):\n')
open(p, "w").write(s)
PY
}

# the other stage, because there are two and the check has to see both
red_2() {
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('def aplicar_registro_ai(escribir):\n'
              '    rc = _sin_subsistema_ai("registro de AI")\n'
              '    if rc is not None:\n'
              '        return rc\n',
              'def aplicar_registro_ai(escribir):\n')
open(p, "w").write(s)
PY
}

# a NEW stage that writes blind into a subsystem that is not there: the
# check has to bite whatever comes, not only the two it already knows.
# That is the difference between watching the class and watching the case.
red_3() {
    cat >> "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'


FUTURE_K8S = os.path.join(RAIZ, "k8s", "base", "future-subsystem", "something.yaml")


def aplicar_future(escribir):
    if escribir:
        open(FUTURE_K8S, "w", encoding="utf-8").write("x")
    return 0
PY
}

# control: a new stage that writes where the artifact DOES have a
# folder needs no guard at all, and turning red on that would be biting
# too much.
control_1() {
    cat >> "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'


LEGITIMATE_K8S = os.path.join(RAIZ, "k8s", "bootstrap", "legitimate.yaml")


def aplicar_legitimate(escribir):
    if escribir:
        open(LEGITIMATE_K8S, "w", encoding="utf-8").write("x")
    return 0
PY
}
