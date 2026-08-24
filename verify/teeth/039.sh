# teeth of check 039 — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# takes out of the artifact exactly what the check claims to measure
red_1() {
    grep -vE 'clusterpolicy-require-aegis-signature.yaml' "$AEGIS_ROOT/init/phases/80-supply-chain.sh" > "$AEGIS_ROOT/init/phases/80-supply-chain.sh.tooth" \
        && mv "$AEGIS_ROOT/init/phases/80-supply-chain.sh.tooth" "$AEGIS_ROOT/init/phases/80-supply-chain.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/80-supply-chain.sh"; }

# The sub-check that could not run must SAY it could not run. Until
# 2026-08-24 the reader's rc was ignored: a malformed kustomization
# made the python fail, the variable came back empty, the grep found
# nothing, and the sub-check reported healthy. Silence as success.
red_9() {
    printf '\nthis: is: not: valid: yaml:\n' \
        >> "$AEGIS_ROOT/seed/platform/k8s/base/kyverno-policies/kustomization.yaml"
}
