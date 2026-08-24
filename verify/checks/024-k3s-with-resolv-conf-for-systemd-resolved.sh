# title: k3s with resolv-conf for systemd-resolved (external bug B)
# origin: verify-static.sh (v2) ══ 24
check() {
# Run #7, bug B outer layer: Ubuntu uses systemd-resolved →
# /etc/resolv.conf is the 127.0.0.53 stub → CoreDNS with no DNS after
# every k3s restart. The fix (config.yaml resolv-conf pointing at the
# real resolv.conf) must be in the bootstrap, conditional on the path
# (portable):
BH="$P/ansible/playbooks/bootstrap-host.yml"
if grep -q 'resolv-conf: /run/systemd/resolve/resolv.conf' "$BH" \
   && grep -q '/run/systemd/resolve/resolv.conf' "$BH" \
   && grep -qE 'when:\s*resolved_real.stat.exists' "$BH"; then
    pass "bootstrap-host: k3s resolv-conf to systemd-resolved (conditional)"
else
    fail "the k3s resolv-conf fix is missing from bootstrap-host (bug B: DNS broken after a restart)"
fi
}
