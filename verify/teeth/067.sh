# dientes del check 067 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
red_1() {
    grep -vE 'wait_rollout jenkins-system sts/jenkins' "$AEGIS_ROOT/init/phases/50-jenkins.sh" > "$AEGIS_ROOT/init/phases/50-jenkins.sh.diente" \
        && mv "$AEGIS_ROOT/init/phases/50-jenkins.sh.diente" "$AEGIS_ROOT/init/phases/50-jenkins.sh"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/init/phases/50-jenkins.sh"; }
