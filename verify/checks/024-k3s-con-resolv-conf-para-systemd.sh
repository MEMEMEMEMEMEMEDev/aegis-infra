# titulo: k3s con resolv-conf para systemd-resolved (bug B externa)
# origen: verify-static.sh (v2) ══ 24
check() {
# Corrida #7, bug B capa externa: Ubuntu usa systemd-resolved →
# /etc/resolv.conf es el stub 127.0.0.53 → CoreDNS sin DNS tras cada
# restart de k3s. El fix (config.yaml resolv-conf al resolv.conf real)
# debe estar en el bootstrap, condicional al path (portable):
BH="$P/ansible/playbooks/bootstrap-host.yml"
if grep -q 'resolv-conf: /run/systemd/resolve/resolv.conf' "$BH" \
   && grep -q '/run/systemd/resolve/resolv.conf' "$BH" \
   && grep -qE 'when:\s*resolved_real.stat.exists' "$BH"; then
    pass "bootstrap-host: k3s resolv-conf a systemd-resolved (condicional)"
else
    fail "falta el fix resolv-conf de k3s en bootstrap-host (bug B: DNS roto tras restart)"
fi
}
