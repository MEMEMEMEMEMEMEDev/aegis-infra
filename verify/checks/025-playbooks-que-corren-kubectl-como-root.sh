# title: playbooks que corren kubectl como root fijan KUBECONFIG (bug B)
# origen: verify-static.sh (v2) ══ 25
check() {
# Corrida #7 (tarea censurada): registry-host-trust corre kubectl con
# become:true (root) y root NO tiene ~/.kube/config → "Extraer ca.crt
# ... FAILED". Todo playbook con become + kubectl pelado debe fijar
# KUBECONFIG al k3s.yaml (644, root lo lee):
RHT="$P/ansible/playbooks/registry-host-trust.yml"
# mira la KEY real `KUBECONFIG:` en línea NO-comentario — el comentario
# que explica el fix también nombra KUBECONFIG (mención ≠ uso; el teeth
# lo reveló, clase check 22/15):
if grep -qE 'kubectl' "$RHT" \
   && ! { nc "$RHT" | grep -qE '^\s*KUBECONFIG:'; }; then
    fail "registry-host-trust usa kubectl (root) SIN KUBECONFIG (bug B: falla como root)"
else
    pass "registry-host-trust: KUBECONFIG explícito para kubectl-como-root"
fi
}
