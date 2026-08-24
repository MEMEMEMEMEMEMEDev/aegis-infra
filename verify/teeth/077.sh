# dientes del check 077 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE 'automountServiceAccountToken: false' "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/bundle.yaml" > "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/bundle.yaml.diente" \
        && mv "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/bundle.yaml.diente" "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/bundle.yaml"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/seed/platform/k8s/organizations/org-canary/bundle.yaml"; }
