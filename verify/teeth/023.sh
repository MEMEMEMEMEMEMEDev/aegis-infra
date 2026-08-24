# teeth of check 023 (every target namespace is created by somebody trustworthy)
# Run #7, bug A: the registry App had CreateNamespace=true but it is
# kustomize/KSOPS, and the sync failed with «namespaces registry-system
# not found». CreateNamespace is not trustworthy for kustomize apps.
red_1() {
    cat >> "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/ci-supply-tenants.yaml" <<'YAML'
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-without-namespace
  namespace: argocd
spec:
  project: plataforma
  source:
    repoURL: git@github.com:__GH_OWNER__/__PLATFORM_REPO__.git
    path: k8s/base/registry-system
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: namespace-that-nobody-creates
YAML
}
