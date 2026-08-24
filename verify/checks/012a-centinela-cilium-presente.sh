# titulo: el centinela de cilium sigue en group_vars
# origen: verify-static.sh (v2) ══ 12, parte a — partida en v3
check() {
# El perfil hetzner necesita cilium y el greenfield no. El centinela
# es el renglón que obliga a mirar antes de asumir que lo de casa vale
# allá; sin él, el perfil se hereda por descuido.
grep -q 'VERIFICAR-ANTES-DE-HETZNER' "$P/ansible/inventory/group_vars/all.yml" \
    && pass "centinela cilium presente" || fail "centinela cilium ausente"
}
