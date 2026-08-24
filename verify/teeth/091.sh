# teeth for check 091 (no public route left unprotected)
# The canary is the only hand-written site, and therefore the easiest
# one to leave without the three middlewares — which is exactly what
# happened in the seed until 2026-08-23.
red_1() {
    python3 - "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/routes.yaml" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
t = re.sub(r'\n\s*- \{name: canary-ritmo\}', '', t, count=1)
open(p, "w").write(t)
PY
}
control_1() { printf '\n# legitimate comment\n' >> "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/routes.yaml"; }
