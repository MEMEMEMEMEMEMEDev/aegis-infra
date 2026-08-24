# teeth of check 019 (tofu: variables with no default ↔ the wrapper's TF_VARs)
# A variable with no default that the wrapper does not inject makes
# tofu ASK on stdin — and in an unattended run that is a hang.
red_1() {
    printf '\nvariable "orphan_variable" {\n  type = string\n}\n' \
        >> "$AEGIS_ROOT/seed/platform/tofu/envs/cloudflare-tunnel/variables.tf"
}
