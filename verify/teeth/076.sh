# teeth for check 076 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'namespace: '\''*'\''' "$AEGIS_ROOT/seed/platform/k8s/bootstrap/appprojects.yaml" > "$AEGIS_ROOT/seed/platform/k8s/bootstrap/appprojects.yaml.tooth" \
        && mv "$AEGIS_ROOT/seed/platform/k8s/bootstrap/appprojects.yaml.tooth" "$AEGIS_ROOT/seed/platform/k8s/bootstrap/appprojects.yaml"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/seed/platform/k8s/bootstrap/appprojects.yaml"; }
