# title: el lab entra por túnel o no entra
# origen: verify-static.sh (v2) ══ 94
check() {
# 2026-08-22: el VPS de laboratorio nació a mano con el 22 abierto y
# recibió escaneo continuo desde el primer día. La causa raíz no era
# «nos escanean» sino «hay un puerto público». Este check congela la
# forma correcta EN EL ARTEFACTO: el cloud-init del lab nace con sshd
# en loopback y sin 22 en ufw, y el env de tofu jamás puede (a) abrir
# el ingreso a otra cosa que el sshd local, (b) pisar el túnel de la
# instancia (aegis-tunnel), ni (c) dejar de marcar el token como
# sensitive (un output no-sensitive aparece EN CLARO en cada plan).
D94=""
VPS_TPL="$P/vps/clouding-lab.cloud-init.yaml.tpl"
VPS_ENV="$P/tofu/envs/vps-lab/main.tf"
if [[ ! -f "$VPS_TPL" ]]; then D94="$D94 falta $VPS_TPL;"
else
    head -1 "$VPS_TPL" | grep -q '^#cloud-config' \
        || D94="$D94 el tpl no empieza con #cloud-config (cloud-init lo IGNORA entero en silencio);"
    python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$VPS_TPL" 2>/dev/null \
        || D94="$D94 el tpl no parsea como YAML;"
    for MAL in 'ufw allow 22' 'allow ssh' 'ssh_pwauth: true' 'fail2ban'; do
        grep -qF "$MAL" "$VPS_TPL" && D94="$D94 el tpl contiene '$MAL' (la máquina nacería con la puerta abierta o con un baneador que banearía al loopback);"
    done
    for BIEN in 'ListenAddress 127.0.0.1' 'PasswordAuthentication no' \
                'PermitRootLogin no' 'NOPASSWD:ALL' \
                'cloudflared service install __CF_TUNNEL_TOKEN__' \
                'rm -f /var/lib/cloud/instance/user-data.txt'; do
        grep -qF "$BIEN" "$VPS_TPL" || D94="$D94 el tpl perdió '$BIEN';"
    done
    # un token REAL pegado en el tpl (los tokens de túnel son JWT:
    # eyJ...) sería la fuga exacta que render/shred existen para evitar:
    grep -qE 'eyJ[A-Za-z0-9_-]{20,}' "$VPS_TPL" \
        && D94="$D94 hay un token REAL pegado en el tpl (eyJ…): rotarlo YA y volver al placeholder;"
fi
if [[ ! -f "$VPS_ENV" ]]; then D94="$D94 falta $VPS_ENV;"
else
    grep -q 'ingress_service *= *"ssh://localhost:22"' "$VPS_ENV" \
        || D94="$D94 el env no ingresa a ssh://localhost:22 (cualquier otro destino expone otra cosa);"
    TN="$(grep -o 'tunnel_name *= *"[^"]*"' "$VPS_ENV" | head -1)"
    [[ -n "$TN" ]] || D94="$D94 el env no declara tunnel_name;"
    [[ "$TN" == *'"aegis-tunnel"'* ]] \
        && D94="$D94 tunnel_name es aegis-tunnel: PISA el túnel de la instancia (la fase 25 y el lab se matarían entre sí);"
    awk '/^output "tunnel_token"/,/^}/' "$VPS_ENV" | grep -q 'sensitive *= *true' \
        || D94="$D94 output tunnel_token sin sensitive=true (el token saldría en claro en cada plan/apply);"
    grep -q 'providers *= *{ *cloudflare *= *cloudflare\.access *}' "$VPS_ENV" \
        || D94="$D94 el módulo de Access no usa el provider access (#76: el token del borde no debe poder tocar Access);"
fi
if [[ -n "$D94" ]]; then fail "94:$D94"
else pass "vps-lab: cloud-init cerrado por diseño, env sin colisiones, token sensitive"; fi
}
