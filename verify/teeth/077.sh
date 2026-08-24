# teeth for check 077 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'automountServiceAccountToken: false' "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/bundle.yaml" > "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/bundle.yaml.tooth" \
        && mv "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/bundle.yaml.tooth" "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/bundle.yaml"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/bundle.yaml"; }
