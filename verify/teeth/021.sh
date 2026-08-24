# dientes del check 021 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
red_1() {
    grep -vE 'rm -f .*\$TUNNEL_ENV/terraform\.tfstate' "$AEGIS_ROOT/init/phases/25-edge-tofu.sh" > "$AEGIS_ROOT/init/phases/25-edge-tofu.sh.diente" \
        && mv "$AEGIS_ROOT/init/phases/25-edge-tofu.sh.diente" "$AEGIS_ROOT/init/phases/25-edge-tofu.sh"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/init/phases/25-edge-tofu.sh"; }
