# dientes del check 035 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
red_1() {
    grep -vE '_jenkins_quota_stall "\$every"' "$AEGIS_ROOT/lib/jenkins.sh" > "$AEGIS_ROOT/lib/jenkins.sh.diente" \
        && mv "$AEGIS_ROOT/lib/jenkins.sh.diente" "$AEGIS_ROOT/lib/jenkins.sh"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/lib/jenkins.sh"; }
