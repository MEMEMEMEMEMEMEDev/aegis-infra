#!/usr/bin/env bash
# aegis-init lib/checks.sh — verificaciones de preflight y de entorno.
# Todas READ-ONLY. Cada check devuelve 0/1 y loguea evidencia (los
# gates exigen evidencia, no "parece que sí").

set -euo pipefail

# ── binarios ────────────────────────────────────────────────────────
# Pines de userland en platform/ansible/inventory/group_vars/all.yml
# (A12: pins literales). check_binaries no instala — fase 05 instala.
REQUIRED_BINS=(tofu sops age age-keygen kubectl helm jq direnv gh \
               python3 git openssl htpasswd ssh-keygen rsync cosign)

check_binaries() {
    local missing=() b
    for b in "${REQUIRED_BINS[@]}"; do
        command -v "$b" >/dev/null || missing+=("$b")
    done
    if ((${#missing[@]})); then
        log_warn "faltan binarios: ${missing[*]}"
        return 1
    fi
    log_ok "userland completo (${#REQUIRED_BINS[@]} binarios)"
}

# yq NO se exige a propósito: la convención del host es python3+pyyaml
# (regla C7); yq solo dentro de pods.

# ── kubeconfig / cluster target ─────────────────────────────────────
# A11: el bache del kubeconfig ajeno casi despliega el tunnel en
# infra de otro proyecto. Verificación POSITIVA del target siempre.
check_kube_context() {
    local expected="$1"
    local current
    current="$(kubectl config current-context 2>/dev/null || echo NONE)"
    if [[ "$current" != "$expected" ]]; then
        log_error "current-context='$current', esperado '$expected'"
        return 1
    fi
    kubectl get nodes -o name >/dev/null || return 1
    log_ok "kubeconfig apunta a '$expected' y responde"
}

check_default_storageclass() {
    # 1.2c: sin default SC los PVC quedan Pending sin error claro.
    kubectl get storageclass -o json | python3 -c '
import sys, json
scs = json.load(sys.stdin)["items"]
d = [s["metadata"]["name"] for s in scs
     if s["metadata"].get("annotations", {}).get(
        "storageclass.kubernetes.io/is-default-class") == "true"]
sys.exit(0 if d else 1)'
}

# ── WSL2 / lado Windows (checklist verificada, no automatizada) ─────
check_wsl2() {
    grep -qi microsoft /proc/version || {
        log_info "no es WSL2 (perfil hetzner: OK)"; return 0; }
    local issues=()
    # systemd activo:
    [[ "$(ps -p 1 -o comm=)" == "systemd" ]] || issues+=("systemd no es PID 1 (wsl.conf [boot] systemd=true)")
    # networking mirrored (best effort: la señal es la IP compartida):
    # NOTA caso-borde: no hay API limpia para leer .wslconfig desde
    # adentro; esto VERIFICA síntomas y GUÍA, no configura (27 §3.3).
    if ((${#issues[@]})); then
        printf '  - %s\n' "${issues[@]}"
        return 1
    fi
    log_ok "WSL2: systemd OK (revisar .wslconfig manualmente si hay dudas de RAM/networking)"
}

# ── precondiciones de cuenta (límites conocidos H4/H5) ──────────────
check_github_reachable() {
    retry_net 3 gh auth status >/dev/null 2>&1
}
check_repo_clean_main() {
    local repo="$1"
    git -C "$repo" fetch origin main --quiet || return 1
    [[ -z "$(git -C "$repo" status --porcelain)" ]] || {
        log_warn "repo $repo con cambios locales"; return 1; }
}

# ── age / SOPS ──────────────────────────────────────────────────────
check_age_key_operational() {
    # A2: la var explícita, no confiar en direnv en non-interactive.
    [[ -n "${SOPS_AGE_KEY_FILE:-}" ]] || {
        log_error "SOPS_AGE_KEY_FILE no exportada"; return 1; }
    [[ -f "$SOPS_AGE_KEY_FILE" ]] || {
        log_error "no existe $SOPS_AGE_KEY_FILE"; return 1; }
    [[ "$(stat -c %a "$SOPS_AGE_KEY_FILE")" == "600" ]] || {
        log_warn "permisos != 600 en la age key"; return 1; }
    log_ok "age key operativa en \$SOPS_AGE_KEY_FILE (600)"
}

check_sops_roundtrip() {
    # roundtrip real contra un archivo del repo (no imprime valores).
    # sops_env: re-deriva SOPS_AGE_KEY_FILE en el punto de uso (bug 5
    # validación #3 — los gates corren en subshells y el export del
    # camino --from tuvo huecos):
    local encfile="$1"
    sops_env
    sops -d "$encfile" | head -c1 >/dev/null
}

# ── host keys de GitHub (pin vs fuente oficial) ─────────────────────
# Los host keys están PINNEADOS en jenkins/values.yaml (T1 declarativo,
# tomados de api.github.com/meta 2026-07-06). Este check detecta
# rotación de GitHub: cada key pinneada debe seguir en /meta. Falla =
# actualizar el values ANTES de bootstrapear (A32: fuente oficial).
check_github_hostkeys_pin() {
    local values="$PLATFORM_DIR/k8s/base/platform/jenkins/values.yaml"
    local meta
    meta="$(mktemp)"
    # gh api (AUTENTICADO, 5000 req/h) y no curl anónimo (60/h): en
    # sesiones de validación iterativa el rate limit anónimo hacía
    # fallar el gate con "(¿red?)" engañoso (bug 2 validación #3).
    # gh ya está garantizado: el gate github-auth corre antes.
    if ! retry_net 3 bash -c "gh api meta > '$meta'"; then
        log_error "gh api meta falló — si el error de arriba dice 'rate limit' NO es red; si es timeout/DNS, revisar la red primero"
        rm -f "$meta"; return 1
    fi
    python3 - "$values" "$meta" <<'EOF'
import json, re, sys
values, meta = open(sys.argv[1]).read(), json.load(open(sys.argv[2]))
official = set(k.split()[1] for k in meta["ssh_keys"])
pinned = set(re.findall(r'github\.com\s+\S+\s+(AAAA\S+)', values))
stale = pinned - official
if stale:
    print("host keys pinneadas que YA NO están en /meta:", file=sys.stderr)
    for k in sorted(stale):
        print(f"  {k[:24]}...", file=sys.stderr)
    sys.exit(1)
sys.exit(0 if pinned else 1)
EOF
    local rc=$?
    rm -f "$meta"
    (( rc == 0 )) && log_ok "host keys pinneadas vigentes según api.github.com/meta"
    return "$rc"
}

# ── red / DNS (preflight-doctor — P0.5 auditoría 2026-07-18) ────────
# La fase 00 no chequeaba NADA de lo que realmente mató corridas
# (IPv6 roto, DNS por NIC apuntando a un resolver muerto, reloj sin
# NTP) — los fallos aparecían a 30-40 min con 4+ fases de estado
# escrito, y el operador los arregló A MANO en la corrida real. El
# doctor verifica Y da la remediación exacta; no configura solo.

# binarios que el PROPIO preflight/wizard necesita (antes de que la
# fase 05 instale el userland): sin esto, la 00 moría con un
# "command not found" críptico en vez de una lista accionable:
check_bootstrap_bins() {
    local missing=() b
    for b in python3 curl git sudo jq; do
        command -v "$b" >/dev/null || missing+=("$b")
    done
    python3 -c 'import yaml' 2>/dev/null || missing+=("python3-yaml")
    if ((${#missing[@]})); then
        log_error "faltan para el preflight: ${missing[*]} — 'sudo apt install ${missing[*]}'"
        return 1
    fi
    log_ok "binarios de bootstrap presentes (python3+yaml, curl, git, sudo, jq)"
}

# resolución REAL de los hosts que el init consume (getent = el
# resolver efectivo del sistema, no un DNS arbitrario):
check_egress_dns() {
    local h bad=()
    for h in github.com api.cloudflare.com get.k3s.io docker.io; do
        retry_net 3 bash -c "getent ahosts '$h' >/dev/null" || bad+=("$h")
    done
    if ((${#bad[@]})); then
        log_error "no resuelven: ${bad[*]} — revisar el resolver POR INTERFAZ ('resolvectl status'): en la corrida real la NIC host-only apuntaba a un DNS muerto y el global tapaba el hueco a ratos"
        return 1
    fi
    log_ok "DNS efectivo resuelve github/cloudflare/k3s/docker"
}

# trampa IPv6 (arreglada A MANO en la corrida real): el host anuncia
# IPv6 pero el camino v6 está roto → curls que cuelgan/fallan según
# a qué familia caiga el happy-eyeballs. Señal: v4 anda y dual falla:
check_ipv6_trap() {
    if curl -fsS -m 15 -o /dev/null https://api.github.com/meta 2>/dev/null; then
        log_ok "egress https OK (dual-stack)"
        return 0
    fi
    if curl -4 -fsS -m 15 -o /dev/null https://api.github.com/meta 2>/dev/null; then
        log_error "el egress FALLA dual-stack pero ANDA forzado a IPv4 — camino IPv6 roto (la trampa de la corrida real). Remediación: sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1 (persistir en /etc/sysctl.d/) o arreglar la ruta v6"
        return 1
    fi
    log_error "el egress https no anda ni por IPv4 — ¿red caída? (reintentar cuando estabilice)"
    return 1
}

# reloj — H1 corrida #15: la VM arrancó ~9h20m ATRASADA con NTP
# "active". timedatectl NO es señal confiable con chrony instalado
# (lee el flag de systemd, no chrony — miente en AMBAS direcciones),
# y chrony corrige por slew: un salto grande tardaría semanas. La
# señal REAL es el skew contra una fuente externa que el init YA
# consume: el header Date de api.github.com. |skew|>60s = ROJO con
# remediación (un reloj corrido hace que certs/tokens recién
# emitidos parezcan not-yet-valid — fallos crípticos 5 fases después):
check_clock_skew() {
    local hdr remote_ts local_ts skew
    hdr="$(retry_net 3 bash -c \
        "curl -fsSI -m 15 https://api.github.com/meta 2>/dev/null \
         | tr -d '\r' | awk 'tolower(\$1)==\"date:\"{ \$1=\"\"; print substr(\$0,2); exit }'")" \
        || { log_warn "no pude leer el header Date de api.github.com — skew de reloj INCONCLUSO (red)"; return 0; }
    [[ -n "$hdr" ]] || { log_warn "respuesta sin header Date — skew inconcluso"; return 0; }
    remote_ts="$(date -ud "$hdr" +%s 2>/dev/null)" || \
        { log_warn "no pude parsear el Date remoto ('$hdr') — skew inconcluso"; return 0; }
    local_ts="$(date -u +%s)"
    skew=$(( local_ts - remote_ts ))
    if (( skew > 60 || skew < -60 )); then
        log_error "RELOJ DESINCRONIZADO: skew ${skew}s contra api.github.com (local $(date -u +%FT%TZ)). Remediación: con chrony 'sudo chronyc makestep'; con timesyncd 'sudo timedatectl set-ntp true && sudo systemctl restart systemd-timesyncd'. Verificar re-corriendo esta fase. OJO: 'timedatectl … synchronized' NO es confiable con chrony"
        return 1
    fi
    log_ok "reloj OK (skew ${skew}s vs api.github.com)"
}

# informativo residual (NO gate — H1: la señal es débil por diseño):
check_clock_ntp() {
    local sync
    sync="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"
    log_info "timedatectl NTPSynchronized=$sync (señal DÉBIL — el veredicto real es el gate de skew)"
    return 0
}

# tmpfs de secretos disponible (secrets_workdir lo asume):
check_dev_shm() {
    local t
    t="$(mktemp -d /dev/shm/aegis-preflight.XXXXXX 2>/dev/null)" || {
        log_error "/dev/shm no escribible — el manejo de secretos (tmpfs+shred) no puede operar"
        return 1; }
    rmdir "$t"
    log_ok "/dev/shm operativo (tmpfs de secretos)"
}

check_domain_on_cloudflare() {
    # 0.6: NS del dominio apuntando a Cloudflare. El check viejo era
    # un NO-OP (sys.exit(0) incondicional — auditoría 2026-07-18):
    # pasaba verde con cualquier dominio y el error real explotaba en
    # la fase 25 (tofu) o 35 (DNS público). Sin dig garantizado en el
    # host: DNS-over-HTTPS contra 1.1.1.1 (curl+jq ya exigidos).
    # FAIL solo con evidencia positiva de NS ajenos; sin respuesta
    # concluyente (red rara) queda WARN — el check duro de la API CF
    # sigue en la fase 25:
    local domain="$1" ns_json ns_list
    ns_json="$(retry_net 3 curl -fsS -m 15 \
        -H 'accept: application/dns-json' \
        "https://1.1.1.1/dns-query?name=${domain}&type=NS" 2>/dev/null)" || {
        log_warn "no pude consultar NS de $domain (DoH 1.1.1.1) — inconcluso; la fase 25 lo valida duro por API"
        return 0; }
    ns_list="$(jq -r '.Answer[]?.data // empty' <<< "$ns_json" | tr -d ' ')"
    if [[ -z "$ns_list" ]]; then
        log_warn "sin registros NS visibles para $domain — ¿zona recién creada? la fase 25 lo valida duro por API"
        return 0
    fi
    if grep -qi 'ns\.cloudflare\.com' <<< "$ns_list"; then
        log_ok "NS de $domain apuntan a Cloudflare"
        return 0
    fi
    printf '%s\n' "$ns_list" >&2
    log_error "los NS de $domain NO son de Cloudflare (arriba) — la zona debe estar activa en tu cuenta CF ANTES del init"
    return 1
}
