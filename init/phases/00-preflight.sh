#!/usr/bin/env bash
# FASE 00 — preflight: precondiciones y límites conocidos.
# El contrato del init es explícito: si una precondición no se
# cumple, se ABORTA ACÁ, no en la fase 40 con medio cluster armado.
# (27 §2.4: los límites H4/H5 se convierten en preflight verificado.)
set -euo pipefail

log_info "Preflight — perfil: $PROFILE"

# ── límites conocidos de v1 (se muestran SIEMPRE) ───────────────────
cat <<'EOF'
LÍMITES CONOCIDOS DE ESTE INIT (v1):
 - NO cubre pérdida total de GitHub (el bootstrap arranca con clone).
 - NO importa recursos Cloudflare/GitHub vivos: perfil greenfield
   RECREA (tunnel nuevo => token nuevo). El perfil re-bootstrap con
   import NO existe todavía.
 - El lado Windows (WSL2/.wslconfig) se VERIFICA y GUÍA, no se
   configura automáticamente.
EOF

# ── precondiciones duras ────────────────────────────────────────────
# 1. Config: GUIADA. Sin conf → el wizard pregunta campo por campo
#    (explicación + default + validación) y lo escribe; con conf
#    válido → sigue de largo (re-corridas). El operador responde
#    preguntas, no edita archivos (misión del operador; mismo
#    principio que los secretos: generar+guiar).
ensure_config    # define y valida todas las vars (lib/config.sh)

# 1b. DOCTOR de host/red (P0.4/P0.5 auditoría 2026-07-18): TODO lo
#     que en corridas reales mató fases a 30-40 min de camino se
#     verifica ACÁ, con la remediación en el mensaje. El doctor
#     diagnostica y guía; no reconfigura el host solo.
# H3 corrida #15: jq frenó la 00 en una VM limpia (prerequisito no
# documentado ni instalado — la 05 instala DESPUÉS de que la 00 lo
# exige). Si hay sudo NOPASSWD, se instala ACÁ, logueado; si no, el
# gate de abajo frena con el comando exacto (como en la #15):
if ! command -v jq >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    log_warn "jq ausente — lo instalo (sudo NOPASSWD disponible; H3 #15)"
    retry_net 3 sudo apt-get -o DPkg::Lock::Timeout=600 install -y jq || \
        log_warn "no pude instalar jq solo — el gate de abajo trae el comando manual"
fi
gate "bootstrap-bins" check_bootstrap_bins
gate "dev-shm" check_dev_shm
gate "egress-ipv6" check_ipv6_trap
gate "dns-efectivo" check_egress_dns
# H1 corrida #15: el veredicto del reloj es el SKEW REAL contra una
# fuente externa (gate duro); timedatectl queda solo informativo:
gate "reloj-sin-skew" check_clock_skew
check_clock_ntp   # informativo (señal débil con chrony — H1)
gate "ns-en-cloudflare" check_domain_on_cloudflare "$ROOT_DOMAIN"

# 1c. sudo TEMPRANO (P0.4): sin NOPASSWD ni operador, la corrida
#     moría en la fase 20 (~30 min). -K purga el cache (el falso
#     positivo de la corrida #5). En interactivo solo avisa (la fase
#     20 va a pedir el password UNA vez); en desatendido es duro:
sudo -K 2>/dev/null || log_info "(sin cache de sudo que purgar)"
if sudo -n true 2>/dev/null; then
    log_ok "sudo NOPASSWD activo — las fases 20/40 corren sin prompt"
elif ni_mode; then
    die "sudo sin NOPASSWD en --non-interactive — instalar ANTES: printf '%s ALL=(ALL) NOPASSWD:ALL\n' \"\$(id -un)\" | sudo tee /etc/sudoers.d/010-aegis-init-nopasswd && sudo chmod 0440 /etc/sudoers.d/010-aegis-init-nopasswd"
else
    log_warn "sudo va a pedir password en la fase 20 (o instalá NOPASSWD ahora para no estar presente: drop-in en /etc/sudoers.d)"
fi

# 2. Host soportado (diseñado sobre Ubuntu 24.04; 26.04 tolerado
#    con aviso — los checks son version-agnósticos, pero el dato
#    queda a la vista si algo raro aparece después):
gate "wsl2-o-linux" check_wsl2
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    log_info "OS detectado: ${PRETTY_NAME:-desconocido}"
    case "${VERSION_ID:-}" in
        24.04|26.04) ;;
        *) log_warn "Ubuntu ${VERSION_ID:-?} no está en la lista probada (24.04/26.04)" ;;
    esac
fi

# 3. gh es PREREQUISITO del operador (instalado + autenticado ANTES
#    del init): es LA credencial GitHub de todo el flujo (D10 — crea
#    repos, settings, webhooks; no hay PAT). Si falta:
#    apt install gh && gh auth login  (scopes: repo + admin de repo)
gate "github-auth" check_github_reachable

# 3b. Host keys de GitHub pinneadas siguen vigentes (A32 — detecta
#     rotación de GitHub ANTES de hornear el values en el cluster):
gate "github-hostkeys-vigentes" check_github_hostkeys_pin

# 4. Espacio en disco (registry+jenkins+trivy PVCs; umbral 20G):
gate "disco-20G" bash -c \
    '[[ $(df --output=avail -BG / | tail -1 | tr -dc 0-9) -ge 20 ]]'

# 5. Greenfield sobre host con kubeconfig previo: confirmar que no
#    se pisa nada vivo (A11 invertido: acá el peligro es PISAR).
if kubectl config current-context >/dev/null 2>&1; then
    log_warn "kubeconfig activo: $(kubectl config current-context)"
    gate_red "greenfield con kubeconfig existente — confirmá que ese cluster NO importa"
fi

# 6. resguardo a mano (agnóstico — el init no asume gestor):
human_step "Resguardo listo" \
  "La fase 10 te va a mostrar la age key UNA vez para que la" \
  "guardes donde guardes tus secretos (gestor, papel, pendrive)." \
  "Es EL ÚNICO valor que vas a resguardar a mano en todo el init" \
  "(el resto se persiste cifrado y se recupera con esa key)." \
  "Tené tu lugar de resguardo accesible AHORA."

log_ok "Preflight completo — límites aceptados, precondiciones OK"
