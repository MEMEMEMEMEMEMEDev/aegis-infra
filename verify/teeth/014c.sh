# dientes del check 014c (el log() del wrapper de tofu a stderr)
# Corrida #6, bug 3: los callers capturan `output -raw tunnel_id` con
# $(); si log() escribe a stdout, el header se pega al valor y el gate
# del token compara contra basura.
red_1() {
    sed -i "s|^log()  { printf .*|log()  { printf '[tofu-wrapper] %s\\\\n' \"\$*\"; }|" \
        "$AEGIS_ROOT/seed/platform/tofu/tofu-apply.sh"
}
control_1() { printf '\n# comentario legitimo sobre log()\n' >> "$AEGIS_ROOT/seed/platform/tofu/tofu-apply.sh"; }
