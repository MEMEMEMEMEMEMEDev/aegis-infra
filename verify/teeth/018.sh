# teeth of check 018 (temporal coupling: entries ↔ sync phase)
#
# Run #4, the bug that stopped phase 35: a static entry whose .enc.yaml
# is generated in a phase LATER than the first sync of its App breaks
# kustomize's ATOMIC build, and then NO secret of that App is created —
# not even the ones that do exist. The symptom shows up far from the
# cause, in another phase and under another name.
#
# Invariant: producing-phase(entry) ≤ phase-of-the-first-argo_sync(App).
# Violating it takes BOTH HALVES: the entry in the generator AND a late
# producer. With the entry alone, the check treats it as «the contract
# path produces it» and moves on — which is correct, and that is why
# the first attempt at this tooth did not bite.
red_1() {
    sed -i 's|^  - secret-github-webhook.enc.yaml.*|  - secret-late.enc.yaml\n&|' \
        "$AEGIS_ROOT/seed/platform/k8s/base/platform/argocd-secrets/secret-generator.yaml"
    printf '\nmake_enc_secret "$PLATFORM_DIR/k8s/base/platform/argocd-secrets/secret-late.enc.yaml"\n' \
        >> "$AEGIS_ROOT/init/phases/80-supply-chain.sh"
}
