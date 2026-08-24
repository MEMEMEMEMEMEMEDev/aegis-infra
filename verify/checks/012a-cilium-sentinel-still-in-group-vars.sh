# title: the cilium sentinel is still in group_vars
# origin: verify-static.sh (v2) ══ 12, part a — split in v3
check() {
# The hetzner profile needs cilium and greenfield does not. The
# sentinel is the line that forces you to look before assuming that
# what works at home works over there; without it, the profile is
# inherited by carelessness.
grep -q 'VERIFICAR-ANTES-DE-HETZNER' "$P/ansible/inventory/group_vars/all.yml" \
    && pass "cilium sentinel present" || fail "cilium sentinel absent"
}
