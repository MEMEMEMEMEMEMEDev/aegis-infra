#!/usr/bin/env bash
# tofu-apply.sh v2 — wrapper OBLIGATORIO para todo tofu (A14).
# Descifra tofu/secrets/tokens.enc.yaml EN MEMORIA y exporta las
# TF_VARs. CAMBIO CLAVE vs v1 (D2/D6/D10): tofu v2 gestiona SOLO
# Cloudflare — ni recursos K8s ni GitHub (repos/settings/webhooks
# van por gh api en el init, fases 12/15). Superficie total del
# wrapper: UN token (CF api), rotable vía tercero. Ni age key, ni
# deploy keys, ni PAT, ni HMAC pasan por acá.
#
# Uso:  ./tofu-apply.sh -chdir=envs/<env> <plan|apply|output> [...]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKENS="$HERE/secrets/tokens.enc.yaml"

# TODO diagnóstico a STDERR — el stdout del wrapper es SAGRADO (H4):
# `exec tofu "$@"` deja pasar el stdout REAL de tofu, y los callers
# capturan subcomandos de lectura con $() — p.ej. `output -raw
# tunnel_id` en la fase 25. Un log a stdout contamina esa captura
# (corrida #6, bug 3: TUNNEL_ID quedó con el header pegado → el gate
# del token nunca matcheaba). Misma clase que log_* de lib/common.sh.
log()  { printf '[tofu-wrapper] %s\n' "$*" >&2; }
die()  { printf '[tofu-wrapper] ERROR: %s\n' "$*" >&2; exit 1; }

command -v tofu >/dev/null || die "tofu no está en PATH"

# EL TOKEN YA EXPORTADO POR EL CALLER TIENE PRECEDENCIA, igual que las
# otras tres TF_VARs de más abajo. No es una excepción: es la MISMA
# regla, aplicada al cuarto valor.
#
# Existe para que CI pueda correr esto SIN LA AGE KEY. El job edge-apply
# recibe únicamente el token de Cloudflare como credencial de Jenkins,
# y con eso el wrapper no necesita descifrar nada. La raíz de confianza
# —la age key— NO entra a CI, nunca.
#
# Es exactamente para lo que D6 achicó la superficie de tofu a un solo
# token de tercero, rotable sin ceremonia: el peor caso de que ese token
# se filtre es una zona de DNS comprometida, no la plataforma entera.
if [[ -n "${TF_VAR_cloudflare_api_token:-}" ]]; then
    log "token inyectado por el caller — no se descifra nada (modo CI)"
    export TF_VAR_cloudflare_api_token
else
    command -v sops >/dev/null || die "sops no está en PATH"
    [[ -n "${SOPS_AGE_KEY_FILE:-}" ]] \
        || die "SOPS_AGE_KEY_FILE no exportada (A2: no confiar en direnv)"
    [[ -f "$TOKENS" ]] || die "no existe $TOKENS"

    # descifrado en memoria; extracción con python3 (no yq — C7):
    decrypted="$(sops -d "$TOKENS")" || die "sops -d falló (¿age key?)"

    get() {
        printf '%s' "$decrypted" | python3 -c "
import sys, yaml
doc = yaml.safe_load(sys.stdin)
v = doc
for k in '$1'.split('.'):
    v = v[k]
print(v['value'] if isinstance(v, dict) else v)"
    }

    export TF_VAR_cloudflare_api_token="$(get cloudflare.api_token)"
    # #76: token SEPARADO para Access. Si el caller ya lo exporto (modo
    # CI) tiene precedencia, igual que los otros — pero el job edge-apply
    # NO deberia recibirlo: la separacion existe para que un CI
    # comprometido no pueda desactivar Access.
    export TF_VAR_cloudflare_access_token="${TF_VAR_cloudflare_access_token:-$(get cloudflare.access_token)}"
    unset decrypted
fi

# ── T1 derivables de la config (D11: lo conocido se DERIVA, jamás
#    se re-pide). Corrida #4: el wrapper inyectaba solo el token y
#    tofu paraba a pedir INTERACTIVAMENTE account_id/zone_id/domain
#    — tres valores que el wizard ya capturó. Fuente: el
#    aegis-init.conf del workspace (o AEGIS_INIT_CONF explícita);
#    un TF_VAR_* ya exportado por el caller tiene precedencia. ────
AEGIS_CONF="${AEGIS_INIT_CONF:-$HERE/../../init/aegis-init.conf}"
if [[ -f "$AEGIS_CONF" ]]; then
    # shellcheck source=/dev/null
    source "$AEGIS_CONF"
    export TF_VAR_cloudflare_account_id="${TF_VAR_cloudflare_account_id:-${CF_ACCOUNT_ID:-}}"
    export TF_VAR_cloudflare_zone_id="${TF_VAR_cloudflare_zone_id:-${CF_ZONE_ID:-}}"
    export TF_VAR_root_domain="${TF_VAR_root_domain:-${ROOT_DOMAIN:-}}"
    # #76: el mail del operador que puede entrar por Access. Sale de
    # ACME_EMAIL y no de una key propia a propósito: es el mismo humano,
    # y dos fuentes para el mismo valor es cómo se desincronizan.
    export TF_VAR_operador_email="${TF_VAR_operador_email:-${ACME_EMAIL:-}}"
fi

# guard: TODA var inyectable presente y sin placeholder — un TF_VAR
# faltante = prompt interactivo de tofu = D11 roto (mejor abortar
# con evidencia que colgar esperando un tipeo):
INJECTED=(TF_VAR_cloudflare_api_token TF_VAR_cloudflare_access_token \
          TF_VAR_cloudflare_account_id \
          TF_VAR_cloudflare_zone_id TF_VAR_root_domain \
          TF_VAR_operador_email)
for v in "${INJECTED[@]}"; do
    [[ "${!v:-}" == PLACEHOLDER_* ]] && die "$v sigue en placeholder"
    [[ -z "${!v:-}" ]] && die "$v vacío — ¿falta $AEGIS_CONF o la key en la config? (exportala como $v para override)"
done

# ── EL STATE (#46) ────────────────────────────────────────────────
#
# El state vive CIFRADO Y VERSIONADO en terraform.tfstate.enc.json, y
# el .tfstate en claro es un archivo de trabajo que nunca entra a git.
#
# POR QUÉ NO EN UN BACKEND REMOTO. El state tiene `tunnel_secret` y el
# token de Cloudflare EN CLARO. Un backend con su propia credencial
# pasaría a custodiar un secreto de PLATAFORMA: quien la consiga levanta
# su propio cloudflared y recibe el tráfico de todos los hostnames. Hoy
# el peor caso de que se filtre el token de CF es una zona de DNS
# comprometida; con el state afuera pasaría a ser el tráfico entero.
# Cifrarlo con la age key no agrega NADA nuevo que cuidar: esa llave ya
# es la raíz de confianza y ya hace falta para recuperar.
#
# LO QUE ESTO CUESTA, dicho de frente: CI no puede aplicar el borde,
# porque descifrar necesita la age key y la age key no entra a CI (§4
# del protocolo). El apply del borde es un comando del operador. A
# cambio, el chequeo de deriva NO usa el state: le pregunta a Cloudflare
# qué hostnames existen y los compara con los derivados de los
# contratos. Ver `bin/aegis-chequeo`.
ENV_ARG=""
for a in "$@"; do
    case "$a" in -chdir=*) ENV_ARG="${a#-chdir=}" ;; esac
done

# Un -chdir ABSOLUTO volvía "$HERE/$ENV_ARG" una ruta basura y TODA la
# maquinaria del state cifrado (#46) se saltaba EN SILENCIO: la fase 85
# aplicó tres veces contra el state plano mientras el enc.json
# envejecía sin que nadie lo supiera (medido 2026-08-21: serial 12 en
# el plano, 11 en el cifrado, y el verificador de rotación pisando el
# bueno con el viejo). Silencio jamás: si cae bajo este árbol se
# normaliza; si no, se muere diciendo por qué.
if [[ -n "$ENV_ARG" && "$ENV_ARG" == /* ]]; then
    if [[ "$ENV_ARG" == "$HERE"/* ]]; then
        ENV_ARG="${ENV_ARG#"$HERE"/}"
    else
        die "-chdir absoluto fuera de $HERE ($ENV_ARG): el state cifrado no sabría dónde vivir (#46) — usar ruta relativa a tofu/"
    fi
fi

CLARO="" ; CIFRADO="" ; HUELLA_ANTES=""
if [[ -n "$ENV_ARG" ]]; then
    CLARO="$HERE/$ENV_ARG/terraform.tfstate"
    CIFRADO="$CLARO.enc.json"
fi

huella() { [[ -f "$1" ]] && sha256sum "$1" | cut -d' ' -f1 || echo "(no existe)"; }

if [[ -n "$CIFRADO" && -f "$CIFRADO" ]]; then
    if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then
        die "hay state cifrado en $(basename "$CIFRADO") pero SOPS_AGE_KEY_FILE no está exportada.
       El state NO se puede leer sin la age key, y eso es a propósito (#46).
       Si esto es CI: este job no puede aplicar el borde. El chequeo de
       deriva que SÍ corre sin la age key está en bin/aegis-chequeo."
    fi
    command -v sops >/dev/null || die "sops no está en PATH"
    # Descifra a un archivo 600 y NO por stdout: el stdout del wrapper es
    # sagrado (H4) y además ahí va el tunnel_secret.
    umask 077
    sops -d "$CIFRADO" > "$CLARO" || die "sops -d del state falló (¿age key correcta?)"
    log "state descifrado ($(python3 -c "import json,sys; print(len(json.load(open('$CLARO')).get('resources',[])))") recursos)"
fi
[[ -n "$CLARO" ]] && HUELLA_ANTES="$(huella "$CLARO")"

# `tofu` y no `exec tofu`: hace falta volver DESPUÉS para recifrar. El
# stdout sigue pasando derecho —los callers capturan `output -raw
# tunnel_id` con $()— porque no se redirige nada acá.
log "TF_VARs inyectadas (${#INJECTED[@]}). Delegando a tofu: $*"
set +e
tofu "$@"
RC=$?
set -e

# Recifrar SOLO si el state cambió. sops produce un texto distinto en
# cada corrida aunque el contenido sea idéntico (clave de datos nueva),
# así que recifrar siempre llenaría git de diffs que no significan nada
# — y un diff que no significa nada es un diff que se deja de leer.
if [[ -n "$CLARO" && -f "$CLARO" && "$(huella "$CLARO")" != "$HUELLA_ANTES" ]]; then
    command -v sops >/dev/null || die "el state cambió y sops no está en PATH"
    umask 077
    sops -e --input-type json --output-type json \
         --filename-override "$CIFRADO" "$CLARO" > "$CIFRADO.tmp" \
        || die "sops -e del state falló"
    mv "$CIFRADO.tmp" "$CIFRADO"
    log "state recifrado -> $(basename "$CIFRADO")  — COMMITEALO"
    log "  sin ese commit, la próxima recuperación no sabe que esto existe."
fi

exit $RC
