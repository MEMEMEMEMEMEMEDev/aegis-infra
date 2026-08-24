# title: preflight-DOCTOR: what killed runs is checked in phase 00 (P0.4/P0.5)
# origin: verify-static.sh (v2) ══ 63
check() {
D63=""
for fn in check_bootstrap_bins check_dev_shm check_ipv6_trap check_egress_dns; do
    nc "$PHASES/00-preflight.sh" | grep -q "$fn" \
        || D63="$D63 phase 00 does not call $fn;"
    nc "$LIBS/checks.sh" | grep -q "^$fn()" \
        || D63="$D63 $fn missing from checks.sh;"
done
nc "$PHASES/00-preflight.sh" | grep -q 'sudo -n true' \
    || D63="$D63 sudo/NOPASSWD is not verified early (it used to surface in phase 20, ~30 min in);"
# the NS check was a NO-OP (an unconditional sys.exit(0)):
CDC63="$(body_of check_domain_on_cloudflare "$LIBS/checks.sh")"
echo "$CDC63" | grep -q 'dns-query' \
    || D63="$D63 check_domain_on_cloudflare still does not really query NS (it was an unconditional sys.exit(0));"
nc "$PHASES/00-preflight.sh" | grep -q 'check_domain_on_cloudflare' \
    || D63="$D63 phase 00 does not validate the domain's NS;"
# phase 05: pyyaml BEFORE the install loop (read_pin imports it). The
# python3-yaml line is a CONTINUATION of the apt install (this check's
# first attempt grepped for 'install -y' on that same line and never
# matched — a tooth that bit the check itself):
L_DEPS="$(nc "$PHASES/05-host.sh" | grep -n 'python3-yaml' | head -1 | cut -d: -f1)"
L_LOOP="$(nc "$PHASES/05-host.sh" | grep -n '^for t in jq git' | head -1 | cut -d: -f1)"
if [[ -z "$L_DEPS" || -z "$L_LOOP" ]] || (( L_DEPS > L_LOOP )); then
    D63="$D63 python3-yaml is installed AFTER the loop that uses read_pin (race on Ubuntu minimal);"
fi
if [[ -n "$D63" ]]; then fail "doctor:$D63"
else pass "phase 00 verifies DNS/IPv6/NTP/shm/sudo/NS with remediation — the 30-minute failures die in minute 1"; fi
}
