#!/usr/bin/env bash
# FASE 05 — host: instala el userland Linux PINNEADO, verifica el
# lado Windows (checklist accionable, no automatización — 27 §3.3).
# Salda H-1: el bootstrap viejo solo VERIFICABA binarios; este los
# instala (el install-cli-tools.yml que el overview nombró y nunca
# existió — overview.md:283).
set -euo pipefail

# ── pins de userland (A12: literales, no channels) ──────────────────
# La fuente de verdad de versiones es group_vars/all.yml del repo de
# plataforma; acá se leen para no duplicar:
PINS_FILE="$PLATFORM_DIR/ansible/inventory/group_vars/all.yml"
gate "pins-presentes" test -f "$PINS_FILE"

read_pin() {  # python3+pyyaml, NO yq (regla C7)
    # clave ausente = FALLO LIMPIO, no traceback (H1 validación #1:
    # git/openssl faltaban y el KeyError crudo escondía el hueco —
    # el fallback silencioso es peor que el fallo explícito):
    python3 -c "
import sys, yaml
pins = yaml.safe_load(open('$PINS_FILE'))['userland_pins']
if '$1' not in pins:
    sys.exit(3)
print(pins['$1'])" || die "pin faltante en userland_pins para '$1' \
(agregarlo a group_vars/all.yml — 'apt' si lo gestiona apt)"
}

# ── apt con espera de lock (bug corrida #10) ────────────────────────
# Al primer boot de una VM, unattended-upgrades tiene el lock de dpkg
# → "could not get lock" y el userland quedaba a medias (htpasswd y
# rsync no se instalaron; el gate userland-completo cazó el hueco).
# apt trae espera NATIVA: DPkg::Lock::Timeout bloquea hasta N segundos
# esperando el lock en vez de fallar. TODO apt-get de esta fase pasa
# por acá (incluido el .deb local de sops — apt instala paths locales,
# dpkg -i no espera locks).
apt_locked() { sudo apt-get -o DPkg::Lock::Timeout=600 "$@"; }

# ── instalación por herramienta (idempotente: si está y coincide el
#    pin, skip; si está con OTRA versión, avisa y NO pisa sin ROJO) ─
# tool_version: primera cadena x.y[.z] que emite el binario. Cada
# tool imprime versión distinto; el regex es el mínimo común.
tool_version() {
    local tool="$1"
    case "$tool" in
        kubectl) kubectl version --client 2>/dev/null ;;
        *)       "$tool" --version 2>/dev/null || "$tool" version 2>/dev/null ;;
    esac | grep -om1 '[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?' || echo desconocida
}

install_tool() {
    local tool="$1" pin ver
    pin="$(read_pin "$tool")"
    if command -v "$tool" >/dev/null; then
        # pin "apt" = SIN pin duro: la presencia basta, no hay
        # versión que comparar (H2 validación #1: comparar la
        # versión real contra el literal "apt" daba drift falso →
        # ROJO en gh, que además es PREREQUISITO autenticado del
        # operador — la fase 00 lo exige antes de que esta corra):
        if [[ "$pin" == "apt" ]]; then
            log_info "$tool presente (gestión apt, sin pin duro)"
            return 0
        fi
        ver="$(tool_version "$tool")"
        if [[ "$ver" == "$pin"* ]]; then
            log_info "$tool $ver ya presente == pin $pin"
        else
            # drift: NO se pisa solo (puede ser deliberado del host);
            # se avisa y el operador decide (A12: el pin manda en
            # greenfield puro; en host con historia, criterio humano).
            log_warn "$tool DRIFT: instalada $ver, pin $pin"
            gate_red "seguir con $tool $ver (≠ pin $pin) — o abortá y alineá el pin/host"
        fi
        return 0
    fi
    # P1.10 auditoría 2026-07-18: (a) TODA descarga con retry_net —
    # eran de UN intento contra la red móvil; (b) tofu instalaba
    # LATEST vía curl|bash (el pin se leía y NO se usaba — corrida no
    # reproducible): ahora va por el .deb VERSIONADO de releases,
    # mismo patrón que sops. Checksums sha256 por artefacto: diferido
    # (exige mantener hashes por versión en group_vars — anotado en
    # VALIDACION §4; los .deb pasan por apt que valida su estructura).
    case "$tool" in
        tofu)   run_cmd retry_net 3 bash -c "curl -fsSLo /tmp/tofu.deb https://github.com/opentofu/opentofu/releases/download/v${pin}/tofu_${pin}_amd64.deb && sudo apt-get -o DPkg::Lock::Timeout=600 install -y /tmp/tofu.deb" ;;
        sops)   run_cmd retry_net 3 bash -c "curl -fsSLo /tmp/sops.deb https://github.com/getsops/sops/releases/download/v${pin}/sops_${pin}_amd64.deb && sudo apt-get -o DPkg::Lock::Timeout=600 install -y /tmp/sops.deb" ;;
        age)    run_cmd retry_net 3 apt_locked install -y age ;;
        kubectl) run_cmd retry_net 3 bash -c "curl -fsSLo /tmp/kubectl https://dl.k8s.io/release/v${pin}/bin/linux/amd64/kubectl && sudo install -m755 /tmp/kubectl /usr/local/bin/" ;;
        helm)   run_cmd retry_net 3 bash -c "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION=v${pin} bash" ;;
        cosign) run_cmd retry_net 3 bash -c "curl -fsSLo /tmp/cosign https://github.com/sigstore/cosign/releases/download/v${pin}/cosign-linux-amd64 && sudo install -m755 /tmp/cosign /usr/local/bin/cosign" ;;
        gh)     run_cmd retry_net 3 apt_locked install -y gh ;;
        direnv) run_cmd retry_net 3 apt_locked install -y direnv ;;
        *)      run_cmd retry_net 3 apt_locked install -y "$tool" ;;
    esac
    # verificación REAL post-install (capability real, no proxy):
    gate "instalado-$tool" command -v "$tool"
}

log_info "Instalando userland pinneado…"
run_cmd retry_net 3 apt_locked update -qq
# deps de apt ANTES del loop (P0.5 auditoría): read_pin usa pyyaml —
# instalarlo DESPUÉS del loop era una carrera contra el Ubuntu
# minimal (sin python3-yaml preinstalado, el primer read_pin moría
# con un die engañoso de "pin faltante"). htpasswd en apache2-utils;
# python3-venv para el venv de ansible de la fase 20 (bug 3
# validación #3: Ubuntu minimal no trae ensurepip):
run_cmd retry_net 3 apt_locked install -y \
    apache2-utils python3-yaml python3-venv rsync
for t in jq git openssl direnv gh age sops tofu kubectl helm cosign; do
    install_tool "$t"
done
gate "userland-completo" check_binaries

# ── direnv hook defensivo (A3) ──────────────────────────────────────
if ! grep -q 'direnv hook bash' ~/.bashrc 2>/dev/null; then
    run_cmd bash -c \
      'echo '\''command -v direnv >/dev/null && eval "$(direnv hook bash)"'\'' >> ~/.bashrc'
    log_ok "hook direnv agregado a .bashrc (defensivo)"
fi

# ── lado Windows: checklist verificada (NO automatizada) ───────────
if grep -qi microsoft /proc/version; then
    human_step "Checklist lado Windows (.wslconfig)" \
      "En %UserProfile%\\.wslconfig verificá:" \
      "  [wsl2]" \
      "  networkingMode=mirrored   (requerido por el stack)" \
      "  memory=  (cap razonable; el host también vive)" \
      "Y que el ext4.vhdx esté en el NVMe." \
      "Si cambiaste algo: 'wsl --shutdown' y volvé a entrar" \
      "(este init retoma con --from 05-host)."
    gate "wsl2-post-checklist" check_wsl2
fi

log_ok "Host listo: userland pinneado instalado y verificado"
