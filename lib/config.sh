#!/usr/bin/env bash
# aegis-init lib/config.sh — configuración GUIADA (misión del
# operador: "el init pregunta y hace; el operador decide y
# confirma — nunca 'completá este archivo'"). Mismo principio que
# los secretos (generar+guiar), aplicado a la config T1.
#
# Flujo: ensure_config()
#   - conf válido presente  → source y seguir (re-corridas y
#     automatización: el .conf pre-hecho SIGUE siendo soportado).
#   - sin conf (o --configure) → wizard: pregunta campo por campo
#     con explicación + default inferido + validación inmediata,
#     muestra el resumen, confirma, y ESCRIBE el .conf.
set -euo pipefail

CONF_FILE="$AEGIS_HOME/aegis.conf"

# ── validadores (uno por tipo de campo; evidencia inmediata) ────────
_v_domain()  { [[ "$1" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; }
_v_email()   { [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; }
_v_reponame(){ [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }
_v_hex32()   { [[ "$1" =~ ^[0-9a-f]{32}$ ]]; }
_v_nonempty(){ [[ -n "$1" ]]; }
_v_path()    { [[ "$1" == /* || "$1" == "\$HOME"* || "$1" == "$HOME"* ]]; }
_v_svc_ip()  {  # dentro del service CIDR default de k3s (10.43/16)
    python3 -c "
import ipaddress, sys
try:
    ip = ipaddress.ip_address('$1')
    sys.exit(0 if ip in ipaddress.ip_network('10.43.0.0/16') else 1)
except ValueError:
    sys.exit(1)"
}

# ── ask <var> <default> <validador> <explicación...> ────────────────
# Pregunta con default entre corchetes (enter = aceptar), valida en
# el momento, reintenta hasta valor válido.
ask() {
    local var="$1" def="$2" validator="$3"; shift 3
    printf '\n\033[1;36m── %s ──\033[0m\n' "$var"
    printf '%s\n' "$@"
    # P0.2 auditoría: con stdin cerrado, read fallaba, ans quedaba
    # vacío, el validador fallaba y el while : reintentaba PARA
    # SIEMPRE (busy-loop infinito — el errexit está suprimido por el
    # contexto || del caller). read || die corta el EOF; el tope de
    # intentos corta el valor persistentemente inválido:
    local ans tries=0
    while :; do
        if [[ -n "$def" ]]; then
            read -rp "  ${var} [${def}]: " ans || \
                die "stdin cerrado en el wizard — para corridas desatendidas: aegis-init.conf pre-hecho + --non-interactive"
            ans="${ans:-$def}"
        else
            read -rp "  ${var}: " ans || \
                die "stdin cerrado en el wizard — para corridas desatendidas: aegis-init.conf pre-hecho + --non-interactive"
        fi
        if "$validator" "$ans"; then break; fi
        tries=$(( tries + 1 ))
        (( tries >= 3 )) && die "3 valores inválidos seguidos para $var — abortando el wizard (revisar el formato pedido arriba)"
        log_warn "valor inválido para $var — de nuevo ($tries/3)"
    done
    printf -v "$var" '%s' "$ans"
}

# ── el wizard ───────────────────────────────────────────────────────
config_wizard() {
    printf '\n\033[1m════ CONFIGURACIÓN GUIADA DE AEGIS v2 ════\033[0m\n'
    printf 'Todo lo de acá es T1 (público/conocido) — CERO secretos.\n'
    printf 'Enter acepta el default entre corchetes.\n'

    # GH_OWNER: inferido de la sesión gh ya autenticada (gate de
    # fase 00 la exige; acá puede no haber corrido aún → best effort)
    local gh_user=""
    gh_user="$(gh api user --jq .login 2>/dev/null || true)"
    ask GH_OWNER "$gh_user" _v_reponame \
      "Owner de GitHub (usuario u org) dueño de los repos de trabajo." \
      "$( [[ -n "$gh_user" ]] && echo '  (inferido de tu sesión gh)' )"

    ask PLATFORM_REPO "ops-stack-v2" _v_reponame \
      "Repo de PLATAFORMA que el init CREA y usa (GitOps lee de acá)." \
      "AISLAMIENTO: es un repo de prueba DESECHABLE del v2 — NO" \
      "apuntes al ops-stack real: el init le escribe commits, tags" \
      "y settings. El default separa v2 de v1 a propósito."

    ask APP_REPO "hello-aegis-v2" _v_reponame \
      "Repo de la APP canary que el init CREA y siembra (el CI le" \
      "escribe builds y le commitea el digest de cada despliegue)." \
      "Mismo aislamiento: NO apuntes al hello-aegis real."

    ask ROOT_DOMAIN "" _v_domain \
      "Dominio raíz (ej: midominio.com). DEBE ser una zona activa" \
      "en tu cuenta de Cloudflare (el tunnel y el DNS viven ahí)." \
      "Subdominios que el init va a usar: argocd.<dominio>," \
      "jenkins.<dominio>."

    local git_email=""
    git_email="$(git config --global user.email 2>/dev/null || true)"
    ask ACME_EMAIL "$git_email" _v_email \
      "Email para el registro ACME de Let's Encrypt (avisos de" \
      "expiración de certificados)."

    ask KUBE_CONTEXT_EXPECTED "default" _v_nonempty \
      "Nombre del context de kubectl que el init EXIGE antes de" \
      "tocar el cluster (A11: el bache del kubeconfig ajeno). k3s" \
      "recién instalado se llama 'default'."

    ask REGISTRY_CLUSTER_IP "10.43.179.123" _v_svc_ip \
      "ClusterIP FIJA del registry interno. Debe caer en el service" \
      "CIDR de k3s (default 10.43.0.0/16) y va pareada con la SAN" \
      "del certificado TLS del registry (el kubelet no resuelve" \
      ".svc — la confianza del host es por esta IP). Se valida el" \
      "rango en el momento."

    ask AEGIS_WORKSPACE "\$HOME/aegis" _v_path \
      "Workspace del operador (para el .envrc de direnv post-init)." \
      "En una VM de validación el default está bien."

    printf '\nLos DOS IDs de Cloudflare son públicos pero hay que\n'
    printf 'buscarlos: dash.cloudflare.com → clic en tu zona (%s)\n' \
        "${ROOT_DOMAIN}"
    printf '→ pestaña Overview → columna derecha, sección "API":\n'
    printf '  - Zone ID\n  - Account ID\nAmbos son 32 hex.\n'
    ask CF_ACCOUNT_ID "" _v_hex32 \
      "Account ID de Cloudflare (32 hex, sección API del Overview)."
    ask CF_ZONE_ID "" _v_hex32 \
      "Zone ID de la zona ${ROOT_DOMAIN} (32 hex, misma sección)."

    # ── resumen + confirmación ──────────────────────────────────────
    printf '\n\033[1m════ RESUMEN ════\033[0m\n'
    local v
    for v in GH_OWNER PLATFORM_REPO APP_REPO ROOT_DOMAIN ACME_EMAIL \
             KUBE_CONTEXT_EXPECTED REGISTRY_CLUSTER_IP AEGIS_WORKSPACE \
             CF_ACCOUNT_ID CF_ZONE_ID; do
        printf '  %-22s = %s\n' "$v" "${!v}"
    done
    local ok
    read -rp $'\n¿Escribo esta config? [S/n] ' ok || \
        die "stdin cerrado en la confirmación del wizard"
    [[ "${ok:-S}" =~ ^[SsYy]?$ ]] || { log_warn "wizard cancelado"; return 1; }

    # ── escritura atómica del .conf ─────────────────────────────────
    local tmp; tmp="$(mktemp)"
    {
        echo "# aegis-init.conf — GENERADO por el wizard ($(date -u +%F))."
        echo "# Editar a mano solo para automatización/re-corridas;"
        echo "# regenerar con: $AEGIS_ROOT/init/aegis-init.sh --configure"
        for v in GH_OWNER PLATFORM_REPO APP_REPO ROOT_DOMAIN ACME_EMAIL \
                 KUBE_CONTEXT_EXPECTED REGISTRY_CLUSTER_IP \
                 CF_ACCOUNT_ID CF_ZONE_ID; do
            printf '%s="%s"\n' "$v" "${!v}"
        done
        # AEGIS_WORKSPACE puede contener $HOME a propósito (sin quote
        # dura — se expande al sourcear):
        printf 'AEGIS_WORKSPACE="%s"\n' "$AEGIS_WORKSPACE"
    } > "$tmp"
    mv "$tmp" "$CONF_FILE"
    log_ok "config escrita en $CONF_FILE"
}

# ── validación de un conf existente (para re-corridas) ──────────────
config_validate() {
    # shellcheck source=/dev/null
    source "$CONF_FILE"
    local missing=() v
    for v in GH_OWNER PLATFORM_REPO APP_REPO ROOT_DOMAIN ACME_EMAIL \
             KUBE_CONTEXT_EXPECTED REGISTRY_CLUSTER_IP \
             CF_ACCOUNT_ID CF_ZONE_ID; do
        [[ -n "${!v:-}" ]] || missing+=("$v")
    done
    if ((${#missing[@]})); then
        log_warn "conf incompleto — faltan: ${missing[*]}"
        return 1
    fi
    _v_domain "$ROOT_DOMAIN" || { log_warn "ROOT_DOMAIN inválido"; return 1; }
    _v_svc_ip "$REGISTRY_CLUSTER_IP" || {
        log_warn "REGISTRY_CLUSTER_IP fuera de 10.43.0.0/16"; return 1; }
    return 0
}

# ── entrypoint ──────────────────────────────────────────────────────
ensure_config() {
    if [[ "${FORCE_CONFIGURE:-false}" == "true" || ! -f "$CONF_FILE" ]]; then
        # P0.1 auditoría: el wizard necesita a alguien que conteste —
        # en desatendido el .conf es PRERREQUISITO, y esto se dice acá:
        ni_mode && die "--non-interactive sin $CONF_FILE — el wizard no corre desatendido; pre-crear el conf (correr una vez '$AEGIS_ROOT/init/aegis-init.sh --configure' con terminal, o escribirlo a mano del template)"
        [[ -f "$CONF_FILE" ]] && log_info "regenerando config (--configure)"
        config_wizard || die "sin config no se puede seguir"
    fi
    config_validate || {
        log_warn "el conf existente no valida — corriendo el wizard"
        config_wizard || die "sin config válida no se puede seguir"
        config_validate || die "config sigue inválida tras el wizard"
    }
    log_ok "config válida: dominio=$ROOT_DOMAIN owner=$GH_OWNER \
repos=$PLATFORM_REPO/$APP_REPO (desechables)"
}
