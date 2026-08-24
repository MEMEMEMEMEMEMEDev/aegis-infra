# teeth for check 094 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'providers *= *{ *cloudflare *= *cloudflare\.access *}' "$AEGIS_ROOT/seed/platform/tofu/envs/vps-lab/main.tf" > "$AEGIS_ROOT/seed/platform/tofu/envs/vps-lab/main.tf.tooth" \
        && mv "$AEGIS_ROOT/seed/platform/tofu/envs/vps-lab/main.tf.tooth" "$AEGIS_ROOT/seed/platform/tofu/envs/vps-lab/main.tf"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/seed/platform/tofu/envs/vps-lab/main.tf"; }
