# dientes del check 091 (ninguna ruta pública sin protección)
# El canario es el único sitio escrito a mano, y por eso el más fácil
# de dejar sin los tres middlewares — que es exactamente lo que pasó
# en la semilla hasta el 2026-08-23.
rojo_1() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/routes.yaml" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
t = re.sub(r'\n\s*- \{name: canary-ritmo\}', '', t, count=1)
open(p, "w").write(t)
PY
}
control_1() { printf '\n# comentario legitimo\n' >> "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/routes.yaml"; }
