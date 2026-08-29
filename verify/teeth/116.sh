# teeth for check 116 (no machine's address is written into the product)
#
# The regression is the one that was live until 2026-08-26: a document
# at the root carrying the lab VPS's public IP, four times, next to its
# break-glass procedure.

# the address comes back where it was.
#
# A DIFFERENT address from the one that was actually there, and that is
# the point: this tooth proves the check bites ANY public address, and
# writing the real one would have carried the operator's VPS in the
# product forever — in the teeth, which are excluded from the sweep, so
# nothing would ever have said so. Found on 2026-08-26 while rehearsing
# the purge of the history: the record came out clean and one blob did
# not, and the blob was this file.
red_1() {
    printf '\n HostName 51.15.42.7\n' >> "$AEGIS_ROOT/Problema-vps-ssh-seguridad.md"
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

# ── the node name (extension of 2026-08-29) ─────────────────────────
# The regression that SHIPPED: the seed installed k3s with the name the
# node has on the machine where the seed was first written, so every
# installation printed one operator's node name in `kubectl get nodes`.
#
# Derived from THIS machine and not written out, for the reason red_1
# above learned: what a tooth writes down it carries forever, in the one
# directory no sweep looks at. It is also the trick check 117 uses —
# here it catches this operator's node, on somebody else's it catches
# theirs.
red_4() {
    sed -i "s/^  --node-name=.*$/  --node-name=$(hostname)-primary/" \
        "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml"
}

# the same name in the Kubernetes spelling, in a manifest — the place
# the sweep would have missed if it only knew the k3s flag
red_5() {
    printf '\n# pinned with nodeName: %s-primary while the GPU was being debugged\n' \
        "$(hostname)" >> "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/core.yaml"
}

# a name is smuggled into the generic table with NO reason — the
# comfortable way to make this check stop asking about it (red_3's
# sibling, one table down)
red_6() {
    python3 - "$AEGIS_ROOT/verify/checks/116-no-machine-address-is-written-into-the-product.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
anchor = "GENERIC_NODES = {\n"
assert t.count(anchor) == 1
open(p, "w").write(t.replace(anchor, anchor + '    "somebodys-laptop": "",\n', 1))
PY
}

# control: the generic name is the one the seed is SUPPOSED to write —
# the same on every installation, so it names nobody
control_4() {
    printf '\n# the seed installs the node as --node-name=aegis-node on every machine\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# control: a hole is not a name. Filling it is the instance's business.
control_5() {
    printf '\n# a chart that pins by hand writes nodeName: __NODE__ and the wizard fills it\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}
