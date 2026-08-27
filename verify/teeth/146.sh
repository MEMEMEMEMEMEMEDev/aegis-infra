# teeth for check 146 (every Application is declared once)
# generated on 2026-08-27 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.

# the canary's second copy comes back under argocd-apps/
red_1() {
    cat >> "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/ci-supply-tenants.yaml" <<'EOF'
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hello-aegis
  namespace: argocd
spec:
  project: aegis-tenant-canary
  source: {repoURL: git@github.com:__GH_OWNER__/__APP_REPO__.git, targetRevision: main, path: k8s/overlays/dev}
  destination: {server: https://kubernetes.default.svc, namespace: org-canary}
EOF
}
# control: a comment in the file is not a declaration
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/ci-supply-tenants.yaml"; }
