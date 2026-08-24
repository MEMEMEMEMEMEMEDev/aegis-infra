# teeth of check 014c (the log() of the tofu wrapper to stderr)
# Run #6, bug 3: the callers capture `output -raw tunnel_id` with $();
# if log() writes to stdout, the header gets glued to the value and the
# token gate compares against garbage.
red_1() {
    sed -i "s|^log()  { printf .*|log()  { printf '[tofu-wrapper] %s\\\\n' \"\$*\"; }|" \
        "$AEGIS_ROOT/seed/platform/tofu/tofu-apply.sh"
}
control_1() { printf '\n# legitimate comment about log()\n' >> "$AEGIS_ROOT/seed/platform/tofu/tofu-apply.sh"; }
