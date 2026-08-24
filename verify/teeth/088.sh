# dientes del check 088 (el alcance de la firma se declara por ETIQUETA)
#
# El incidente del 2026-07-27: el ClusterPolicy scopeaba
# `namespaces: [org-personal]`. Se creó org-portafolio, se desplegó
# ahí, y esa organización nació FUERA de la verificación de firma. No
# hubo error ni aviso: la política simplemente no la miraba, y se
# admitió una imagen pública sin firmar con todo el tablero en verde.
#
# Una lista solo puede nombrar lo que ya existe; la etiqueta la lleva
# el bundle de cada inquilino, así que la cobertura llega con la
# organización.
red_1() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/base/kyverno-policies/clusterpolicy-require-aegis-signature.yaml" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p).read()
# se reemplaza el selector por etiqueta por la lista de namespaces que
# el incidente probó insuficiente
t = re.sub(r'(?m)^(\s*)namespaceSelector:\n(?:\1  .*\n)+',
           lambda m: f"{m.group(1)}namespaces: [org-canary]\n", t, count=1)
open(p, "w").write(t)
PY
}
