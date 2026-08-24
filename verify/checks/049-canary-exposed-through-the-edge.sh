# title: the canary is EXPOSED through the edge, and its repo does NOT write the route (CR-5 #14 / #54)
# origin: verify-static.sh (v2) ══ 49
check() {
# THE INVARIANT IS "the canary is reachable from the edge", not "the
# file is in such and such folder". Until 2026-08-11 this check
# demanded seed/canary/k8s/base/ingressroute.yaml, and with #54 the
# route moved over to the platform side: the check would have gone RED
# over a correct artifact, which is the class C15 already noted twice
# in this file (a check tied to the LOCATION lies as soon as something
# moves).
#
# And the move is not cosmetic. `traefik.io/IngressRoute` is in the
# namespaceResourceBlacklist of aegis-tenant-canary, so if the canary's
# repo still brought it along, its Application would not sync —the
# canary would stop starting because of the very control that protects
# it—. That is why the two halves are verified together.
D49=""
SEED_BASE="$AEGIS_ROOT/seed/canary/k8s/base"
# (a) the canary's repo does NOT bring routing: neither the file nor the entry.
[[ -f "$SEED_BASE/ingressroute.yaml" ]] \
    && D49="$D49 the canary's repo still brings ingressroute.yaml (a kind forbidden in its AppProject: its App will not sync);"
grep -qE '^\s*-\s*ingressroute\.yaml\s*$' "$SEED_BASE/kustomization.yaml" \
    && D49="$D49 the canary's kustomization still lists ingressroute.yaml;"
# (b) the route exists ON THE PLATFORM SIDE, with the Host by
#     placeholder, and the right entryPoint and Service.
CR="$P/k8s/organizations/org-canary/routes.yaml"
if [[ -f "$CR" ]]; then
    CR_NC="$(nc "$CR")"
    echo "$CR_NC" | grep -q 'aegis\.__ROOT_DOMAIN__' \
        || D49="$D49 the canary's routing does not match aegis.__ROOT_DOMAIN__ (hardcoded domain?);"
    echo "$CR_NC" | grep -qE 'entryPoints:.*\bweb\b|^\s*-\s*web\s*$' \
        || D49="$D49 the canary's routing does not use the web entryPoint;"
    echo "$CR_NC" | grep -q 'name: hello-aegis' \
        || D49="$D49 the canary's routing does not point at the hello-aegis Service;"
else
    D49="$D49 k8s/organizations/org-canary/routes.yaml is missing: the canary has no route ANYWHERE;"
fi
# (c) and it is delivered: listed in the organization's kustomization.
grep -qE '^\s*-\s*routes\.yaml' "$P/k8s/organizations/org-canary/kustomization.yaml" \
    || D49="$D49 routes.yaml not listed in the org-canary kustomization (A19: the file exists and nobody applies it);"
# (d) and the kind is effectively forbidden for the canary's project.
python3 - "$P/k8s/bootstrap/appprojects.yaml" <<'PY' || D49="$D49 aegis-tenant-canary does not forbid traefik.io/IngressRoute (the canary could claim somebody else's Host);"
import sys, yaml
for d in yaml.safe_load_all(open(sys.argv[1])):
    if d and d.get("metadata", {}).get("name") == "aegis-tenant-canary":
        bl = d["spec"].get("namespaceResourceBlacklist", [])
        sys.exit(0 if any(e.get("group") == "traefik.io" and e.get("kind") == "IngressRoute"
                          for e in bl) else 1)
sys.exit(1)
PY
if [[ -n "$D49" ]]; then fail "canary edge:$D49"
else pass "the canary's route is placed by the platform (org-canary/routes.yaml, delivered), its repo cannot write it and the AppProject prevents it"; fi
}
