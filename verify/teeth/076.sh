# dientes del check 076 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE 'namespace: '\''*'\''' "$AEGIS_ROOT/semilla/plataforma/k8s/bootstrap/appprojects.yaml" > "$AEGIS_ROOT/semilla/plataforma/k8s/bootstrap/appprojects.yaml.diente" \
        && mv "$AEGIS_ROOT/semilla/plataforma/k8s/bootstrap/appprojects.yaml.diente" "$AEGIS_ROOT/semilla/plataforma/k8s/bootstrap/appprojects.yaml"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/semilla/plataforma/k8s/bootstrap/appprojects.yaml"; }
