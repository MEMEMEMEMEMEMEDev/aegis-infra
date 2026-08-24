# dientes del check 049 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE 'entryPoints:.*\bweb\b|^\s*-\s*web\s*$' "$AEGIS_ROOT/semilla/plataforma/k8s/organizations/org-canary/ruteo.yaml" > "$AEGIS_ROOT/semilla/plataforma/k8s/organizations/org-canary/ruteo.yaml.diente" \
        && mv "$AEGIS_ROOT/semilla/plataforma/k8s/organizations/org-canary/ruteo.yaml.diente" "$AEGIS_ROOT/semilla/plataforma/k8s/organizations/org-canary/ruteo.yaml"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/semilla/plataforma/k8s/organizations/org-canary/ruteo.yaml"; }
