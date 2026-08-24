# dientes del check 082 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE '"\$TOFU".*destroy' "$AEGIS_ROOT/libexec/aegis-destroy" > "$AEGIS_ROOT/libexec/aegis-destroy.diente" \
        && mv "$AEGIS_ROOT/libexec/aegis-destroy.diente" "$AEGIS_ROOT/libexec/aegis-destroy"
}
