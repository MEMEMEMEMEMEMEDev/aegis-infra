# dientes del check 025 (kubectl como root fija KUBECONFIG)
# Corrida #7: registry-host-trust corre kubectl con become:true y root
# NO tiene ~/.kube/config → "Extraer ca.crt ... FAILED" a mitad de la
# fase 40.
red_1() {
    sed -i '/^[[:space:]]*KUBECONFIG:/d' "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml"
}
# control: el comentario que EXPLICA el fix también nombra KUBECONFIG.
# Si el check mordiera la mención en vez del uso, esto lo delataría.
control_1() {
    printf '\n# nota: KUBECONFIG hace falta porque root no lee el del usuario\n' \
        >> "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml"
}
