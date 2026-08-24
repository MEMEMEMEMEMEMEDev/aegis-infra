# title: the lab comes in through the tunnel or it does not come in
# origin: verify-static.sh (v2) ══ 94
check() {
# 2026-08-22: the laboratory VPS was born by hand with 22 open and
# received continuous scanning from day one. The root cause was not «we
# get scanned» but «there is a public port». This check freezes the
# correct shape IN THE ARTIFACT: the lab's cloud-init is born with sshd
# on loopback and without 22 in ufw, and tofu's env can never (a) open
# the ingress to anything other than the local sshd, (b) overwrite the
# instance's tunnel (aegis-tunnel), nor (c) stop marking the token as
# sensitive (a non-sensitive output appears IN THE CLEAR in every plan).
D94=""
VPS_TPL="$P/vps/clouding-lab.cloud-init.yaml.tpl"
VPS_ENV="$P/tofu/envs/vps-lab/main.tf"
if [[ ! -f "$VPS_TPL" ]]; then D94="$D94 $VPS_TPL missing;"
else
    head -1 "$VPS_TPL" | grep -q '^#cloud-config' \
        || D94="$D94 the tpl does not start with #cloud-config (cloud-init IGNORES it entirely, in silence);"
    python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$VPS_TPL" 2>/dev/null \
        || D94="$D94 the tpl does not parse as YAML;"
    for BAD in 'ufw allow 22' 'allow ssh' 'ssh_pwauth: true' 'fail2ban'; do
        grep -qF "$BAD" "$VPS_TPL" && D94="$D94 the tpl contains '$BAD' (the machine would be born with the door open, or with a banner that would ban the loopback);"
    done
    for GOOD in 'ListenAddress 127.0.0.1' 'PasswordAuthentication no' \
                'PermitRootLogin no' 'NOPASSWD:ALL' \
                'cloudflared service install __CF_TUNNEL_TOKEN__' \
                'rm -f /var/lib/cloud/instance/user-data.txt'; do
        grep -qF "$GOOD" "$VPS_TPL" || D94="$D94 the tpl lost '$GOOD';"
    done
    # a REAL token pasted into the tpl (tunnel tokens are JWTs: eyJ...)
    # would be the exact leak that render/shred exist to avoid:
    grep -qE 'eyJ[A-Za-z0-9_-]{20,}' "$VPS_TPL" \
        && D94="$D94 there is a REAL token pasted into the tpl (eyJ…): rotate it NOW and go back to the placeholder;"
fi
if [[ ! -f "$VPS_ENV" ]]; then D94="$D94 $VPS_ENV missing;"
else
    grep -q 'ingress_service *= *"ssh://localhost:22"' "$VPS_ENV" \
        || D94="$D94 the env does not ingress to ssh://localhost:22 (any other destination exposes something else);"
    TN="$(grep -o 'tunnel_name *= *"[^"]*"' "$VPS_ENV" | head -1)"
    [[ -n "$TN" ]] || D94="$D94 the env does not declare tunnel_name;"
    [[ "$TN" == *'"aegis-tunnel"'* ]] \
        && D94="$D94 tunnel_name is aegis-tunnel: it OVERWRITES the instance's tunnel (phase 25 and the lab would kill each other);"
    awk '/^output "tunnel_token"/,/^}/' "$VPS_ENV" | grep -q 'sensitive *= *true' \
        || D94="$D94 output tunnel_token without sensitive=true (the token would come out in the clear on every plan/apply);"
    grep -q 'providers *= *{ *cloudflare *= *cloudflare\.access *}' "$VPS_ENV" \
        || D94="$D94 the Access module does not use the access provider (#76: the edge's token must not be able to touch Access);"
fi
if [[ -n "$D94" ]]; then fail "94:$D94"
else pass "vps-lab: cloud-init closed by design, env without collisions, token sensitive"; fi
}
