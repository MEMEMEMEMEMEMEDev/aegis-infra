# dientes del check 005 (los paths de git de las Applications existen)
# Una App apuntando a un directorio que no está en el repo queda
# «Unknown» para siempre, y el motivo no aparece en ninguna alerta.
red_1() {
    sed -i '0,/^    path: /s|^    path: .*|    path: k8s/base/directorio-que-no-existe|' \
        "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/ci-supply-tenants.yaml"
}
control_1() { printf '\n# comentario legitimo\n' >> "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/ci-supply-tenants.yaml"; }
