# teeth for check 116 (no machine's address is written into the product)
#
# The regression is the one that was live until 2026-08-26: a document
# at the root carrying the lab VPS's public IP, four times, next to its
# break-glass procedure.

# the address comes back where it was
red_1() {
    printf '\n HostName <IP-DEL-VPS>\n' >> "$AEGIS_ROOT/Problema-vps-ssh-seguridad.md"
}

# and in a place nobody would think to look: a comment inside a phase.
# An address does not stop being an address because it is commented out.
# A GLOBALLY ROUTABLE one on purpose: the documentation ranges of RFC
# 5737 name nobody and the check ignores them by design, so a tooth
# written with one proves nothing — which is exactly what the first
# version of this tooth did.
red_2() {
    printf '\n# the VPS answered at 51.15.42.7 during the rehearsal\n' \
        >> "$AEGIS_ROOT/init/phases/25-edge-tofu.sh"
}

# a machine is smuggled into the allowlist with NO reason — the
# comfortable way to make this check stop asking about it
red_3() {
    python3 - "$AEGIS_ROOT/verify/checks/116-no-machine-address-is-written-into-the-product.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
anchor = "ALLOWED = {\n"
assert t.count(anchor) == 1
open(p, "w").write(t.replace(anchor, anchor + '    "51.15.42.7": "",\n', 1))
PY
}

# control: a private address names nobody — it is the same everywhere,
# and the artifact is full of them on purpose (10.43.0.80 is traefik)
control_1() {
    printf '\n# the bridge forwards to 10.43.0.80 and the pods live in 10.42.0.0/16\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# control: the version numbers this tree actually writes (three
# components) are not addresses and must not bite
control_2() {
    printf '\n# tested against traefik chart 40.3.0 and blackbox v0.28.0\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# control: a FOUR-component version, which does parse as an address, is
# legitimate when it is declared — and the declaration has to work, or
# the escape hatch is decoration
control_3() {
    printf '\n# not-an-address: cloud-init 26.1.0.4 is the version the VPS shipped with\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}
