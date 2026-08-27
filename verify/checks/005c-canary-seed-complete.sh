# title: canary seed complete
# origin: verify-static.sh (v2) ══ 5c
check() {
SEED_MISSING=""
for f in main.go go.mod Containerfile README.md \
         k8s/base/deployment.yaml k8s/base/kustomization.yaml \
         k8s/overlays/dev/kustomization.yaml; do
    [[ -f "$AEGIS_ROOT/seed/canary/$f" ]] || SEED_MISSING="$SEED_MISSING $f"
done
# What the canary's tree does NOT carry — the Jenkinsfile and every
# `ci/<script>` that Jenkinsfile runs — phase 12 has to place from the
# canonical templates folder. Derived from the template, not listed by
# hand: a new `node ci/x` in the Jenkinsfile is a new file phase 12
# must ship. Found on 2026-08-27: the first canary build on a clean
# instance died in `desplegar` with MODULE_NOT_FOUND on write-digest.mjs.
JT="$SEED/platform/docs/protocols/templates/Jenkinsfile.app"
P12="$(nc "$PHASES/12-workrepos.sh")"
for script in $(grep -oE 'node ci/[A-Za-z0-9_.-]+' "$JT" 2>/dev/null | awk '{print $2}' | sort -u); do
    base="${script#ci/}"
    [[ -f "$SEED/platform/docs/protocols/templates/$base" ]] \
        || SEED_MISSING="$SEED_MISSING (no canonical templates/$base for the Jenkinsfile's '$script')"
    echo "$P12" | grep -q "templates/$base" \
        || SEED_MISSING="$SEED_MISSING (phase 12 does not place $script, which the Jenkinsfile runs)"
done
if [[ -n "$SEED_MISSING" ]]; then fail "canary seed incomplete:$SEED_MISSING"
else pass "canary seed complete (the Jenkinsfile and the ci/ scripts it runs are placed from the templates by phase 12)"; fi
}
