# teeth of check 049 — generated on 2026-08-23 and VERIFIED: every red
# was applied over a copy of the tree and the check went red.

# takes out of the artifact exactly what the check claims to measure
red_1() {
    grep -vE 'entryPoints:.*\bweb\b|^\s*-\s*web\s*$' "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/routes.yaml" > "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/routes.yaml.tooth" \
        && mv "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/routes.yaml.tooth" "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/routes.yaml"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/routes.yaml"; }
