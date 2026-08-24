# dientes del check 007 (los resources de las kustomizations existen)
# kustomize es ATÓMICO: un resource inexistente rompe el build entero y
# NINGÚN objeto de esa App se aplica, ni los que sí estaban bien.
rojo_1() {
    printf '  - archivo-que-no-existe.yaml\n' >> \
        "$AEGIS_ROOT/seed/platform/k8s/base/platform/jenkins/kustomization.yaml"
}
