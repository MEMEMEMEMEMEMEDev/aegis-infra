# teeth for check 134 (the seed is pure artifact)
# Half of v2's debt came from having the same code in two places and a
# whole tool to watch that they did not drift apart.
red_1() {
    mkdir -p "$AEGIS_ROOT/seed/platform/bin"
    printf '#!/usr/bin/env bash\necho hello\n' > "$AEGIS_ROOT/seed/platform/bin/aegis-something"
    chmod +x "$AEGIS_ROOT/seed/platform/bin/aegis-something"
}
red_2() {
    printf '#!/usr/bin/env bash\n' > "$AEGIS_ROOT/seed/platform/k8s/stray-script.sh"
    chmod +x "$AEGIS_ROOT/seed/platform/k8s/stray-script.sh"
}
