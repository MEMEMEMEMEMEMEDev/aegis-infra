# titulo: el canary EXPONE por el edge, y la ruta NO la escribe su repo (CR-5 #14 / #54)
# origen: verify-static.sh (v2) ══ 49
check() {
# EL INVARIANTE ES "el canary se alcanza desde el edge", no "el archivo
# está en tal carpeta". Hasta el 2026-08-11 este check exigía
# seed/canary/k8s/base/ingressroute.yaml, y con #54 la ruta se mudó
# al lado de la plataforma: el check habría dado ROJO sobre un artefacto
# correcto, que es la clase C15 ya anotada dos veces en este archivo (un
# check atado a la UBICACIÓN miente en cuanto algo se mueve).
#
# Y la mudanza no es cosmética. `traefik.io/IngressRoute` está en el
# namespaceResourceBlacklist de aegis-tenant-canary, así que si el repo
# del canario siguiera trayéndola, su Application no sincronizaría —el
# canario dejaría de arrancar por el control que lo protege—. Por eso
# las dos mitades se verifican juntas.
D49=""
SEED_BASE="$AEGIS_ROOT/seed/canary/k8s/base"
# (a) el repo del canario NO trae ruteo: ni el archivo ni la entry.
[[ -f "$SEED_BASE/ingressroute.yaml" ]] \
    && D49="$D49 el repo del canario todavía trae ingressroute.yaml (kind prohibido en su AppProject: su App no va a sincronizar);"
grep -qE '^\s*-\s*ingressroute\.yaml\s*$' "$SEED_BASE/kustomization.yaml" \
    && D49="$D49 el kustomization del canario todavía lista ingressroute.yaml;"
# (b) la ruta existe DEL LADO DE LA PLATAFORMA, con el Host por
#     placeholder, el entryPoint y el Service correctos.
CR="$P/k8s/organizations/org-canary/routes.yaml"
if [[ -f "$CR" ]]; then
    CR_NC="$(nc "$CR")"
    echo "$CR_NC" | grep -q 'aegis\.__ROOT_DOMAIN__' \
        || D49="$D49 el ruteo del canario no matchea aegis.__ROOT_DOMAIN__ (¿dominio hardcodeado?);"
    echo "$CR_NC" | grep -qE 'entryPoints:.*\bweb\b|^\s*-\s*web\s*$' \
        || D49="$D49 el ruteo del canario no usa el entryPoint web;"
    echo "$CR_NC" | grep -q 'name: hello-aegis' \
        || D49="$D49 el ruteo del canario no apunta al Service hello-aegis;"
else
    D49="$D49 falta k8s/organizations/org-canary/routes.yaml: el canario no tiene ruta en NINGÚN lado;"
fi
# (c) y está entregada: listada en el kustomization de la organización.
grep -qE '^\s*-\s*routes\.yaml' "$P/k8s/organizations/org-canary/kustomization.yaml" \
    || D49="$D49 routes.yaml no listado en el kustomization de org-canary (A19: el archivo existe y no lo aplica nadie);"
# (d) el kind está efectivamente prohibido para el proyecto del canario.
python3 - "$P/k8s/bootstrap/appprojects.yaml" <<'PY' || D49="$D49 aegis-tenant-canary no prohíbe traefik.io/IngressRoute (el canario podría reclamar el Host de otro);"
import sys, yaml
for d in yaml.safe_load_all(open(sys.argv[1])):
    if d and d.get("metadata", {}).get("name") == "aegis-tenant-canary":
        bl = d["spec"].get("namespaceResourceBlacklist", [])
        sys.exit(0 if any(e.get("group") == "traefik.io" and e.get("kind") == "IngressRoute"
                          for e in bl) else 1)
sys.exit(1)
PY
if [[ -n "$D49" ]]; then fail "edge del canary:$D49"
else pass "la ruta del canary la pone la plataforma (org-canary/routes.yaml, entregada), su repo no puede escribirla y el AppProject lo impide"; fi
}
