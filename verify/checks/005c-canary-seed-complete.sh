# title: canary seed complete
# origin: verify-static.sh (v2) ══ 5c
check() {
SEED_MISSING=""
for f in main.go go.mod Containerfile README.md \
         k8s/base/deployment.yaml k8s/base/kustomization.yaml \
         k8s/overlays/dev/kustomization.yaml; do
    [[ -f "$AEGIS_ROOT/seed/canary/$f" ]] || SEED_MISSING="$SEED_MISSING $f"
done
if [[ -n "$SEED_MISSING" ]]; then fail "canary seed incomplete:$SEED_MISSING"
else pass "canary seed complete (the Jenkinsfile is instantiated from the template in phase 12)"; fi
}
