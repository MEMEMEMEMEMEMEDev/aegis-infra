# dientes del check 073 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE 'webhook_serving cert-manager' "$AEGIS_ROOT/init/phases/35-gitops.sh" > "$AEGIS_ROOT/init/phases/35-gitops.sh.diente" \
        && mv "$AEGIS_ROOT/init/phases/35-gitops.sh.diente" "$AEGIS_ROOT/init/phases/35-gitops.sh"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/init/phases/35-gitops.sh"; }
