# dientes del check 094 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# saca del artefacto justo lo que el check dice medir
rojo_1() {
    grep -vE 'providers *= *{ *cloudflare *= *cloudflare\.access *}' "$AEGIS_ROOT/seed/platform/tofu/envs/vps-lab/main.tf" > "$AEGIS_ROOT/seed/platform/tofu/envs/vps-lab/main.tf.diente" \
        && mv "$AEGIS_ROOT/seed/platform/tofu/envs/vps-lab/main.tf.diente" "$AEGIS_ROOT/seed/platform/tofu/envs/vps-lab/main.tf"
}

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/seed/platform/tofu/envs/vps-lab/main.tf"; }
