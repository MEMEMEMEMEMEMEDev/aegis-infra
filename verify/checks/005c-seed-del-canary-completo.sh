# titulo: seed del canary completo
# origen: verify-static.sh (v2) ══ 5c
check() {
SEED_MISSING=""
for f in main.go go.mod Containerfile README.md \
         k8s/base/deployment.yaml k8s/base/kustomization.yaml \
         k8s/overlays/dev/kustomization.yaml; do
    [[ -f "$AEGIS_ROOT/seed/canary/$f" ]] || SEED_MISSING="$SEED_MISSING $f"
done
if [[ -n "$SEED_MISSING" ]]; then fail "seed canary incompleto:$SEED_MISSING"
else pass "seed canary completo (Jenkinsfile se instancia del template en fase 12)"; fi
}
