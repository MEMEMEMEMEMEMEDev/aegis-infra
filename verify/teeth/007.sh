# teeth of check 007 (the resources of the kustomizations exist)
# kustomize is ATOMIC: a nonexistent resource breaks the whole build
# and NO object of that App is applied, not even the ones that were
# fine.
red_1() {
    printf '  - file-that-does-not-exist.yaml\n' >> \
        "$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/kustomization.yaml"
}
