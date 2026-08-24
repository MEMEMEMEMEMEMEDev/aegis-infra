# dientes del check 065 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE 'gen_or_restore redis_auth' "$AEGIS_ROOT/init/phases/30-argocd.sh" > "$AEGIS_ROOT/init/phases/30-argocd.sh.diente" \
        && mv "$AEGIS_ROOT/init/phases/30-argocd.sh.diente" "$AEGIS_ROOT/init/phases/30-argocd.sh"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/init/phases/30-argocd.sh"; }
