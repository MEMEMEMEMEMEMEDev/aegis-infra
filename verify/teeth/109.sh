# dientes del check 109 (ninguna etapa escribe en un subsistema ausente)
#
# La mutación correcta es la REGRESIÓN, no un parecido: sacarle la
# guarda a la etapa y dejarla como estaba el 2026-08-24, cuando `aegis
# org apply` moría con FileNotFoundError después de haber escrito seis
# manifiestos.
rojo_1() {
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

# la otra etapa, porque son dos y el check tiene que ver las dos
rojo_2() {
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

# una etapa NUEVA que escribe a ciegas en un subsistema que no está:
# el check tiene que morder lo que venga, no solo las dos que ya
# conoce. Es la diferencia entre vigilar la clase y vigilar el caso.
rojo_3() {
    cat >> "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'


FUTURO_K8S = os.path.join(RAIZ, "k8s", "base", "subsistema-futuro", "algo.yaml")


def aplicar_futuro(escribir):
    if escribir:
        open(FUTURO_K8S, "w", encoding="utf-8").write("x")
    return 0
PY
}

# control: una etapa nueva que escribe donde el artefacto SÍ tiene
# carpeta no necesita guarda ninguna, y ponerse rojo con eso sería
# morder de más.
control_1() {
    cat >> "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'


LEGITIMO_K8S = os.path.join(RAIZ, "k8s", "bootstrap", "legitimo.yaml")


def aplicar_legitimo(escribir):
    if escribir:
        open(LEGITIMO_K8S, "w", encoding="utf-8").write("x")
    return 0
PY
}
