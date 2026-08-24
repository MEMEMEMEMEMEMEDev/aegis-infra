# teeth of check 025 (kubectl as root sets KUBECONFIG)
# Run #7: registry-host-trust runs kubectl with become:true and root
# does NOT have ~/.kube/config → "Extraer ca.crt ... FAILED" halfway
# through phase 40.
red_1() {
    sed -i '/^[[:space:]]*KUBECONFIG:/d' "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml"
}
# control: the comment that EXPLAINS the fix also names KUBECONFIG. If
# the check bit the mention instead of the use, this would give it
# away.
control_1() {
    printf '\n# note: KUBECONFIG is needed because root does not read the user one\n' \
        >> "$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml"
}
