# dientes del check 019 (tofu: variables sin default ↔ TF_VARs del wrapper)
# Una variable sin default que el wrapper no inyecta hace que tofu
# PREGUNTE por stdin — y en una corrida desatendida eso es un cuelgue.
rojo_1() {
    printf '\nvariable "variable_huerfana" {\n  type = string\n}\n' \
        >> "$AEGIS_ROOT/seed/platform/tofu/envs/cloudflare-tunnel/variables.tf"
}
