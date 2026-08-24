# title: preflight-DOCTOR: lo que mató corridas se chequea en la 00 (P0.4/P0.5)
# origen: verify-static.sh (v2) ══ 63
check() {
D63=""
for fn in check_bootstrap_bins check_dev_shm check_ipv6_trap check_egress_dns; do
    nc "$PHASES/00-preflight.sh" | grep -q "$fn" \
        || D63="$D63 la 00 no llama $fn;"
    nc "$LIBS/checks.sh" | grep -q "^$fn()" \
        || D63="$D63 falta $fn en checks.sh;"
done
nc "$PHASES/00-preflight.sh" | grep -q 'sudo -n true' \
    || D63="$D63 sudo/NOPASSWD no se verifica temprano (se descubría en la 20, a ~30 min);"
# el check de NS era un NO-OP (sys.exit(0) incondicional):
CDC63="$(body_of check_domain_on_cloudflare "$LIBS/checks.sh")"
echo "$CDC63" | grep -q 'dns-query' \
    || D63="$D63 check_domain_on_cloudflare sigue sin consultar NS de verdad (era sys.exit(0) incondicional);"
nc "$PHASES/00-preflight.sh" | grep -q 'check_domain_on_cloudflare' \
    || D63="$D63 la 00 no valida NS del dominio;"
# fase 05: pyyaml ANTES del loop de install (read_pin lo importa).
# La línea de python3-yaml es una CONTINUACIÓN del apt install (el
# primer intento de este check grepeaba 'install -y' en esa misma
# línea y no matcheaba nunca — diente que mordió al propio check):
L_DEPS="$(nc "$PHASES/05-host.sh" | grep -n 'python3-yaml' | head -1 | cut -d: -f1)"
L_LOOP="$(nc "$PHASES/05-host.sh" | grep -n '^for t in jq git' | head -1 | cut -d: -f1)"
if [[ -z "$L_DEPS" || -z "$L_LOOP" ]] || (( L_DEPS > L_LOOP )); then
    D63="$D63 python3-yaml se instala DESPUÉS del loop que usa read_pin (carrera en Ubuntu minimal);"
fi
if [[ -n "$D63" ]]; then fail "doctor:$D63"
else pass "la 00 verifica DNS/IPv6/NTP/shm/sudo/NS con remediación — los fallos de 30 min mueren en el minuto 1"; fi
}
