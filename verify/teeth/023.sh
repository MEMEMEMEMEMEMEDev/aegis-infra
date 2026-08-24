# dientes del check 023 (cada namespace destino lo crea alguien confiable)
# Corrida #7, bug A: la App registry tenía CreateNamespace=true pero es
# kustomize/KSOPS, y el sync falló con «namespaces registry-system not
# found». CreateNamespace no es confiable para apps kustomize.
rojo_1() {
    cat >> "$AEGIS_ROOT/semilla/plataforma/k8s/argocd-apps/ci-supply-tenants.yaml" <<'YAML'
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-sin-namespace
  namespace: argocd
spec:
  project: plataforma
  source:
    repoURL: git@github.com:__GH_OWNER__/__PLATFORM_REPO__.git
    path: k8s/base/registry-system
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: namespace-que-nadie-crea
YAML
}
