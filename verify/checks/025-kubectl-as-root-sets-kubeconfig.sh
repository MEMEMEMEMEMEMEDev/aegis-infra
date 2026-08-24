# title: playbooks running kubectl as root set KUBECONFIG (bug B)
# origin: verify-static.sh (v2) ══ 25
check() {
# Run #7 (censored task): registry-host-trust runs kubectl with
# become:true (root) and root does NOT have ~/.kube/config → "Extraer
# ca.crt ... FAILED". Every playbook with become + a bare kubectl must
# set KUBECONFIG to the k3s.yaml (644, root can read it):
RHT="$P/ansible/playbooks/registry-host-trust.yml"
# looks at the real KEY `KUBECONFIG:` on a NON-comment line — the
# comment explaining the fix also names KUBECONFIG (mention ≠ use; the
# tooth revealed it, class of checks 22/15):
if grep -qE 'kubectl' "$RHT" \
   && ! { nc "$RHT" | grep -qE '^\s*KUBECONFIG:'; }; then
    fail "registry-host-trust uses kubectl (root) WITHOUT KUBECONFIG (bug B: fails as root)"
else
    pass "registry-host-trust: explicit KUBECONFIG for kubectl-as-root"
fi
}
