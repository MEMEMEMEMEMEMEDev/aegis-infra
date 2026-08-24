#!/usr/bin/env bash
# aegis-init lib/common.sh — logging, gates, pausas humanas, estado.
# Cargada por aegis-init.sh; las fases la reciben ya sourceada.
# Reglas horneadas: pasos de revert NUNCA con && (cada paso con exit
# code visible); niveles VERDE/AMARILLO/ROJO como funciones de gate.

set -euo pipefail

: "${AEGIS_ROOT:?common.sh requiere AEGIS_ROOT (el PRODUCTO). Lo exporta bin/aegis; un libexec invocado a mano lo resuelve con readlink -f de su propio path}"

# Producto e instancia: un solo resolvedor, en lib/paths.sh (02 §1).
# shellcheck source=paths.sh
source "$AEGIS_ROOT/lib/paths.sh"

: "${CHECK_MODE:=false}"
: "${PROFILE:=greenfield}"
: "${AEGIS_NONINTERACTIVE:=false}"

# ── constantes de plataforma (P3 auditoría 2026-07-18) ──────────────
# REG_HOST estaba duplicado A MANO en 4 fases (40/50/70/80) — una
# divergencia rompería cert/mirror/netrc/policy a la vez. Fuente única:
REGISTRY_HOST_INTERNAL="registry.registry-system.svc.cluster.local:5000"

# ── modo desatendido (P0.1 auditoría 2026-07-18) ────────────────────
# ni_mode: --non-interactive / AEGIS_ASSUME_YES=true. El init corre
# de 0 a fin SIN operador: human_step y gate_red se auto-confirman
# (la autorización la dio el flag — pensado para VM greenfield
# DESECHABLE y para el CI del propio init). Los secretos de entrada
# van por archivo (CF_MASTER_FILE / AEGIS_AGE_BACKUP_FILE, tmpfs).
# La EXCEPCIÓN deliberada: decisiones que podrían pisar recursos NO
# marcados como desechables (repo sin marcador) MUEREN en vez de
# auto-confirmarse — desatendido no es carta blanca sobre lo ajeno.
ni_mode() { [[ "${AEGIS_NONINTERACTIVE:-false}" == "true" ]]; }

# ── logging ──────────────────────────────────────────────────────────
# TODO log va a STDERR (hallazgo 4 de la validación #1): el stdout
# de una función-que-retorna-valor es SAGRADO — capturarla con $()
# debe dar SOLO el valor. Un log_info en stdout dentro de gen_*
# contaminó el path retornado y rompió la ceremonia de la age key.
# verify-static vigila que esta convención no regrese (check 14).
_ts() { date '+%H:%M:%S'; }
log_info()  { printf '\033[1;34m[%s INFO ]\033[0m %s\n' "$(_ts)" "$*" >&2; }
log_ok()    { printf '\033[1;32m[%s  OK  ]\033[0m %s\n' "$(_ts)" "$*" >&2; }
log_warn()  { printf '\033[1;33m[%s WARN ]\033[0m %s\n' "$(_ts)" "$*" >&2; }
log_error() { printf '\033[1;31m[%s ERROR]\033[0m %s\n' "$(_ts)" "$*" >&2; }
die()       { log_error "$*"; exit 1; }

phase_todo() { log_warn "TODO: $*"; }

# ── estado por fase (para --from y resumen) ─────────────────────────
# Un archivo-marca por fase completada. Idempotencia barata y legible.
mark_done()   { mkdir -p "$AEGIS_STATE_DIR"; : > "$AEGIS_STATE_DIR/$1.done"; }
is_done()     { [[ -f "$AEGIS_STATE_DIR/$1.done" ]]; }
clear_state() { rm -rf "$AEGIS_STATE_DIR"; }

# ── modo check ──────────────────────────────────────────────────────
# run_cmd: en CHECK_MODE muestra sin ejecutar. SOLO para comandos que
# MUTAN. Las lecturas se ejecutan siempre (un dry-run que no lee no
# valida nada — lección check_mode de Ansible, 2026-05-01).
run_cmd() {
    if [[ "$CHECK_MODE" == "true" ]]; then
        log_info "[check] $*"
    else
        "$@"
    fi
}

# ── pausas humanas ──────────────────────────────────────────────────
# human_step: la ÚNICA forma de pedir acción externa. Muestra QUÉ
# hacer, DÓNDE, y espera confirmación. Nunca lee el valor secreto por
# acá (eso es de lib/secrets.sh, que no lo muestra).
human_step() {
    local title="$1"; shift
    printf '\n\033[1;35m══ ACCIÓN HUMANA ══ %s\033[0m\n' "$title"
    printf '%s\n' "$@"
    if [[ "$CHECK_MODE" == "true" ]]; then
        log_info "[check] (pausa humana omitida)"
        return 0
    fi
    if ni_mode; then
        log_info "(--non-interactive: pausa humana auto-confirmada)"
        return 0
    fi
    # || die (P0 auditoría): sin TTY, read recibe EOF y con errexit
    # vivo la fase moría con un error mudo — el die dice la causa:
    read -rp $'\nListo? [enter para continuar / ctrl-c para abortar] ' _ \
        || die "stdin cerrado en una pausa humana — sin terminal, correr con --non-interactive"
}

# ── registro máquina-legible de gates (P2.13 reporte in-VM #14) ─────
# Cada gate apendea UNA línea JSON a $AEGIS_STATE_DIR/gates.jsonl
# (ts, fase, gate, resultado, duración): un agente diagnostica
# corridas históricas con jq, sin parsear ANSI del log humano. Los
# nombres de gate son slugs fijos (sin comillas ni backslash) — el
# printf plano alcanza, no hace falta un serializador. Best-effort a
# propósito: el registro JAMÁS puede voltear un gate:
_gate_record() {   # <gate> <pass|fail> <duration_s>
    { mkdir -p "$AEGIS_STATE_DIR" && \
      printf '{"ts":"%s","phase":"%s","gate":"%s","result":"%s","duration_s":%s}\n' \
        "$(date -u +%FT%TZ)" "${AEGIS_PHASE:-}" "$1" "$2" "$3" \
        >> "$AEGIS_STATE_DIR/gates.jsonl"; } 2>/dev/null || true
}

# ── gates ───────────────────────────────────────────────────────────
# gate: verificación con evidencia. Falla la fase si falla el gate.
# El nombre queda en el log — los gates son el contrato de cada fase.
gate() {
    local name="$1"; shift
    local t0=$SECONDS
    if "$@"; then
        _gate_record "$name" pass $(( SECONDS - t0 ))
        log_ok "GATE $name"
    else
        _gate_record "$name" fail $(( SECONDS - t0 ))
        die "GATE $name FALLÓ — la fase no puede continuar"
    fi
}

# ── entrada REAL en lista YAML (H4 corrida #13, bug SISTÉMICO) ──────
# Los guards de idempotencia de los same-commit usaban `grep -q` del
# NOMBRE del archivo — pero el COMENTARIO que documenta el patrón
# contiene ese mismo nombre → el guard matcheaba el comentario → el
# paso quedaba "ya hecho" → la entry JAMÁS se agregaba → recurso
# huérfano sin pista (el caso que lo motivó: el CR del Image Updater
# y su regcred, los dos retirados en #59;
# 2 latentes: cosign y el policy de firma). Mención ≠ uso, aplicado
# a YAML: solo cuenta la ENTRY de lista (`- archivo`), nunca el
# comentario. TODO guard de same-commit pasa por acá (check 41):
yaml_lists_file() {   # <yaml> <basename>
    # Tolera comentario al final de línea. Sin el `(#.*)?`, una entry
    # documentada (`- x.enc.yaml  # lo cifra la fase 85`) era invisible
    # para el guard y la fase la insertaba DE NUEVO — kustomize murió
    # con «already registered id» en el primer encendido de la 85
    # (2026-08-20). El comentario es YAML válido; el guard tenía que
    # leer YAML, no líneas.
    grep -qE "^\s*-\s*${2//./\\.}\s*(#.*)?$" "$1"
}

# ── ¿este manifiesto tiene algún objeto? (A/B del H4) ───────────────
# Un manifiesto DERIVADO puede estar legítimamente vacío: sus
# documentos salen de otra cosa, y esa otra cosa puede no existir
# todavía. El caso: k8s/bootstrap/appprojects-tenants.yaml lo genera
# `bin/aegis-org` desde orgs/*.yaml, y una instancia recién arrancada
# tiene CERO contratos — el archivo llega con su encabezado y sin un
# solo documento. `kubectl apply -f` sobre eso NO es un no-op:
#
#     error: no objects passed to apply     (rc 1)
#
# y con set -e mata la fase 35. O sea que la semilla no arrancaría por
# el mismo motivo por el que es correcta.
#
# Estructural y no textual, por la misma razón que yaml_lists_file: el
# encabezado del archivo NOMBRA los kinds que documenta, así que un
# `grep -q AppProject` daría verdadero sobre un archivo sin objetos —
# el H4 otra vez, ahora al revés.
yaml_has_docs() {   # <yaml>
    python3 - "$1" <<'EOF'
import sys, yaml
try:
    docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
except Exception as e:
    print(f"YAML ilegible: {e}", file=sys.stderr); sys.exit(2)
sys.exit(0 if docs else 1)
EOF
}

# ── inyección de placeholder multi-línea (CR-1/CR-2 corrida #14) ────
# La familia HERMANA del H4, aplicada a las INYECCIONES: el
# replace() global de la fase 80 volcó el PEM también en el
# COMENTARIO que documentaba el placeholder (CR-1: YAML top-level
# roto, kustomize "missing Resource metadata") y el next() del CA
# tomó el indent de la PRIMERA ocurrencia — que era un comentario —
# rompiendo el block scalar (CR-2: helm "did not find expected
# key"). Misma clase que H6 (material multi-línea que no respeta la
# estructura del destino). EL ÚNICO camino para inyectar contenido
# multi-línea en un YAML del artefacto (check 48):
#   (a) solo cuentan líneas NO-comentario (los comentarios quedan
#       intactos, documenten lo que documenten);
#   (b) se exige EXACTAMENTE UNA ocurrencia no-comentario;
#   (c) el indent sale de ESA línea (la real, no un comentario);
#   (d) el YAML resultante se VALIDA antes de escribir — si no
#       parsea, el destino queda intacto y la fase muere acá, no
#       tres gates después con un error de kustomize/helm.
inject_placeholder() {   # <yaml_destino> <placeholder> <archivo_contenido>
    python3 - "$1" "$2" "$3" <<'EOF'
import sys, yaml
target, ph, content_path = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(target).read()
lines = text.splitlines()
hits = [i for i, l in enumerate(lines)
        if ph in l and not l.lstrip().startswith("#")]
if len(hits) != 1:
    sys.exit(f"inject_placeholder: {ph} tiene {len(hits)} ocurrencias "
             f"no-comentario en {target} (se exige EXACTAMENTE 1)")
i = hits[0]
indent = lines[i][: len(lines[i]) - len(lines[i].lstrip())]
block = ("\n" + indent).join(open(content_path).read().strip().splitlines())
lines[i] = lines[i].replace(ph, block)
out = "\n".join(lines) + ("\n" if text.endswith("\n") else "")
try:
    list(yaml.safe_load_all(out))
except Exception as e:
    sys.exit(f"inject_placeholder: el YAML resultante de {target} NO "
             f"parsea ({e}) — el archivo queda INTACTO")
open(target, "w").write(out)
EOF
}

# guard de idempotencia de las inyecciones: ¿queda una ocurrencia
# VIVA (no-comentario) del placeholder? En re-run ya no queda y la
# inyección se salta (inject_placeholder con 0 ocurrencias MUERE a
# propósito — mejor explícito que silencioso):
placeholder_pending() {   # <yaml> <placeholder>
    grep -vE '^\s*#' "$1" | grep -qF "$2"
}

# ── gate con diagnóstico al fallar (H7 corrida #13) ─────────────────
# Cada timeout MUDO de la corrida #13 tenía el error exacto escondido
# en un status (operationState del App, events del ns, describe del
# pod). gate_diag = gate, pero al fallar EJECUTA el diagnóstico dado
# antes de morir — el operador ve la causa, no solo el nombre:
gate_diag() {   # <name> <diag_bash_string> <cmd...>
    local name="$1" diag="$2"; shift 2
    local t0=$SECONDS
    if "$@"; then
        _gate_record "$name" pass $(( SECONDS - t0 ))
        log_ok "GATE $name"
    else
        _gate_record "$name" fail $(( SECONDS - t0 ))
        log_warn "GATE $name falló — evidencia:"
        # eval (no bash -c): el diagnóstico puede usar funciones de
        # las libs (jenkins_get, etc.), no solo binarios:
        eval "$diag" >&2 || true
        die "GATE $name FALLÓ — la causa real está en la evidencia de arriba"
    fi
}

# gate_red: acciones ROJO (irreversibles/secretos) SIEMPRE confirman,
# incluso corriendo "sin frenos". El init automatiza mecánica, no
# decisiones irreversibles (principio secreto-al-operador).
gate_red() {
    local why="$1"
    printf '\n\033[1;31m══ ROJO ══\033[0m %s\n' "$why"
    [[ "$CHECK_MODE" == "true" ]] && { log_info "[check] (rojo omitido)"; return 0; }
    # P0.1 auditoría: en --non-interactive el ROJO se auto-confirma —
    # la afirmación deliberada la dio el operador AL PASAR EL FLAG
    # (contrato: VM greenfield desechable / CI del init). Se loguea
    # FUERTE para que el gates.jsonl y el log dejen rastro de qué se
    # auto-aprobó. Las decisiones sobre recursos ajenos no pasan por
    # acá en NI (los callers mueren antes — ver ensure_repo fase 12):
    if ni_mode; then
        log_warn "ROJO auto-confirmado por --non-interactive: $why"
        return 0
    fi
    # la propiedad de seguridad es la afirmación DELIBERADA (la
    # palabra completa), no la caja de las letras (H3 validación #1:
    # "si" en minúsculas abortó sin explicación). No se acepta "s"
    # ni Enter solo:
    local ans
    read -rp 'Escribí SI (mayúsculas o minúsculas) para continuar — cualquier otra cosa aborta: ' ans \
        || die "stdin cerrado en un gate ROJO — sin terminal, correr con --non-interactive"
    [[ "${ans^^}" == "SI" ]] || die "Abortado por el operador en gate ROJO"
}

# ── render de placeholders de clase-config ──────────────────────────
# render_platform_placeholders: EL ÚNICO dueño del reemplazo de los
# placeholders derivables de aegis-init.conf/$PROFILE en platform/
# (T1). Los de clase-generado tienen dueño de fase y NO se tocan acá:
# __AGE_PUBLIC__ (fase 10), __COSIGN_PUB__ y __AEGIS_CA_PEM__ (fase
# 80), __OBS_CA_PEM__ y __OBS_NTFY_{OPERADOR,PUENTE}_HASH__ (fase
# 85). Idempotente: sin placeholders vivos es no-op. Verifica al
# final que ninguno de clase-config sobreviva (falla explícita, no
# manifest a medio renderizar).
#
# Los 5 de observabilidad se DERIVAN de $PROFILE (fase-85 §4: valores
# concretos por placeholder, no un nombre-de-perfil que exigiría
# maquinaria de templating nueva). El perfil es identidad de
# NACIMIENTO: cambiar --profile en un re-run NO re-renderiza (el
# placeholder ya murió) — cambiarlo después es editar los valores en
# git. Tabla (consumidores en k8s/base/observability/):
#
#   placeholder                 greenfield  hetzner  consumidor
#   __AEGIS_PROFILE__           greenfield  hetzner  external_labels de vmagent (identidad del dato)
#   __OBS_RETENCION_METRICAS__  30d         90d      vmsingle retentionPeriod
#   __OBS_RETENCION_LOGS__      7d          30d      vlogs retentionPeriod
#   __OBS_CF_CAIDO_FOR__        30m         5m       regla cloudflared (for:) — dev se cae por diseño
#   __OBS_DEADMAN_REPEAT__      24h         6h       route del deadman (repeat_interval) — a 6h en dev
#                                                    el operador aprendería a ignorar el hueco nocturno
#
# (la retención de eventos, 1y, NO es placeholder: no varía por perfil
#  — un valor constante disfrazado de variable es una mentira de
#  flexibilidad)
_CONFIG_PLACEHOLDERS='__\(GH_OWNER\|PLATFORM_REPO\|APP_REPO\|ROOT_DOMAIN\|REGISTRY_CLUSTER_IP\|ACME_EMAIL\|AEGIS_PROFILE\|OBS_RETENCION_METRICAS\|OBS_RETENCION_LOGS\|OBS_CF_CAIDO_FOR\|OBS_DEADMAN_REPEAT\)__'
render_platform_placeholders() {
    : "${GH_OWNER:?}" "${PLATFORM_REPO:?}" "${APP_REPO:?}" \
      "${ROOT_DOMAIN:?}" "${REGISTRY_CLUSTER_IP:?}" "${ACME_EMAIL:?}" \
      "${PROFILE:?}"
    local obs_ret_metricas obs_ret_logs obs_cf_caido_for obs_deadman_repeat
    case "$PROFILE" in
        hetzner) obs_ret_metricas=90d obs_ret_logs=30d
                 obs_cf_caido_for=5m  obs_deadman_repeat=6h ;;
        *)       obs_ret_metricas=30d obs_ret_logs=7d
                 obs_cf_caido_for=30m obs_deadman_repeat=24h ;;
    esac
    local f
    while IFS= read -r f; do
        run_cmd sed -i \
            -e "s|__GH_OWNER__|$GH_OWNER|g" \
            -e "s|__PLATFORM_REPO__|$PLATFORM_REPO|g" \
            -e "s|__APP_REPO__|$APP_REPO|g" \
            -e "s|__ROOT_DOMAIN__|$ROOT_DOMAIN|g" \
            -e "s|__REGISTRY_CLUSTER_IP__|$REGISTRY_CLUSTER_IP|g" \
            -e "s|__ACME_EMAIL__|$ACME_EMAIL|g" \
            -e "s|__AEGIS_PROFILE__|$PROFILE|g" \
            -e "s|__OBS_RETENCION_METRICAS__|$obs_ret_metricas|g" \
            -e "s|__OBS_RETENCION_LOGS__|$obs_ret_logs|g" \
            -e "s|__OBS_CF_CAIDO_FOR__|$obs_cf_caido_for|g" \
            -e "s|__OBS_DEADMAN_REPEAT__|$obs_deadman_repeat|g" \
            "$f"
        log_info "render: ${f#"$PLATFORM_DIR"/}"
    done < <(grep -rl "$_CONFIG_PLACEHOLDERS" "$PLATFORM_DIR" \
             --exclude='*.tpl' 2>/dev/null || true)
    if [[ "$CHECK_MODE" != "true" ]] && \
       grep -rq "$_CONFIG_PLACEHOLDERS" "$PLATFORM_DIR" --exclude='*.tpl'; then
        grep -rl "$_CONFIG_PLACEHOLDERS" "$PLATFORM_DIR" --exclude='*.tpl'
        die "render incompleto: quedan placeholders de clase-config"
    fi
}

# poll <timeout_s> <every_s> <cmd...> — reintenta hasta que el
# comando pase o venza el timeout. Para esperas largas (builds,
# rollouts fuera de kubectl wait); retry_net es para egress puntual.
poll() {
    local timeout="$1" every="$2"; shift 2
    # P3 auditoría: el waited viejo NO contaba la duración del comando
    # (un probe de 20s hacía que "300s de timeout" fueran 300s de
    # sleep + N×20s de probes). SECONDS mide tiempo REAL transcurrido:
    local t0=$SECONDS
    until "$@"; do
        (( SECONDS - t0 >= timeout )) && return 1
        sleep "$every"
    done
}

# ── argo_sync CANÓNICO (una sola definición — bug C corrida #8) ─────
# Historia: cada fase definía su argo_sync local (patch + wait de
# health). Bug C: si la App YA estaba Healthy (típico en --from), el
# wait de health retorna INSTANTÁNEO sin esperar al sync recién
# disparado → la lectura de operationState veía "Running" → gate
# falso-negativo. Y el patch contra una App que el root sync aún no
# creó fallaba con "not found" (patrón timing #8: reintentar sin
# cambiar nada lo "arreglaba").
# Este argo_sync: (1) espera a que la App EXISTA (poll — creación
# async por el root); (2) dispara el sync; (3) espera la fase
# TERMINAL de la operación NUEVA — distinguida de la anterior por
# startedAt, así un Succeeded viejo no se lee como el resultado del
# sync nuevo — con corte RÁPIDO en Failed/Error (fallo real ≠
# no-convergió-todavía); (4) recién entonces exige Healthy.
# Devuelve 1 en fallo (con log) — set -e lo hace fatal en el caller,
# y `argo_sync X || retry` permite reintentos deliberados.
argo_sync() {   # <app> [timeout_s]
    local app="$1" timeout="${2:-300}"
    log_info "sync $app"
    if ! poll 180 5 bash -c \
         "kubectl -n argocd get application '$app' -o name >/dev/null 2>&1"; then
        log_error "App $app no existe tras 180s (¿el root sync corrió?)"
        _gate_record "sync-$app" fail 180
        return 1
    fi
    local prev_started
    prev_started="$(kubectl -n argocd get application "$app" \
        -o jsonpath='{.status.operationState.startedAt}' 2>/dev/null || true)"
    # P1.3 auditoría (carrera selfHeal en vuelo, confirmada en la
    # corrida real): con automated+selfHeal una operación puede estar
    # CORRIENDO en el momento del patch → ArgoCD rechaza el patch con
    # "another operation is already in progress" y el sync moría como
    # fallo real. Esa operación en curso ES el sync que queremos: se
    # ADOPTA (prev_started="" hace que cualquier fase terminal cuente).
    # H5 corrida #15 (LA SOBRE-CORRECCIÓN del bug C, mordió en vivo:
    # 17 min mudos + fase 50 muerta con el sistema SANO): el tercer
    # caso es patch ACEPTADO pero NO-OP — la App (automated) conserva
    # un `.operation` residual del sync automático y el merge de un
    # sync vacío sobre otro sync no cambia NADA ("patched (no
    # change)") → jamás habrá startedAt nuevo → exigir "operación
    # nueva" espera algo que no va a existir. Se captura el output
    # del patch para detectarlo; la aceptación del estado presente va
    # en el loop (regla nueva: todo fix de carrera con condición "es
    # nuevo" contempla el caso "el estado deseado YA existía"):
    if [[ "$CHECK_MODE" == "true" ]]; then
        log_info "[check] kubectl -n argocd patch application $app (operation.sync)"
        return 0
    fi
    # Hallazgo D v1.2 (LA causa de "namespaces cert-manager not
    # found", y un bug LATENTE en las 17 corridas anteriores): un
    # sync manual disparado con `operation.sync` VACÍO **no hereda
    # spec.syncPolicy.syncOptions**. Evidencia en vivo (ArgoCD
    # v3.4.3): specOpts=[ServerSideApply,CreateNamespace] pero
    # opOpts=null, y en el syncResult NO figura el Namespace — la
    # tarea de crearlo nunca entró. Hasta ahora funcionaba de rebote:
    # el AUTO-sync (que sí usa las opciones del spec) creaba el ns
    # minutos antes de que llegara nuestro sync manual. Al adelantar
    # cert-manager (fix del Hallazgo A) llegamos primero y el chart
    # se aplicó contra un namespace inexistente. Peor: ArgoCD
    # entonces marca "failed previous sync attempt ... will not
    # retry" y el auto-sync DEJA de reintentar esa revisión — el
    # fallo manual envenena la recuperación automática.
    # Fix: el sync manual lleva EXPLÍCITAMENTE las opciones del spec.
    local sync_patch='{"operation":{"sync":{}}}' spec_opts
    spec_opts="$(kubectl -n argocd get application "$app" \
        -o jsonpath='{.spec.syncPolicy.syncOptions}' 2>/dev/null || true)"
    if [[ "$spec_opts" == \[*\] ]]; then
        sync_patch="{\"operation\":{\"sync\":{\"syncOptions\":$spec_opts}}}"
        log_info "sync $app: opciones del spec propagadas a la operación ($spec_opts)"
    fi
    local patch_out="" patch_rc=0 sync_noop=false
    patch_out="$(kubectl -n argocd patch application "$app" --type merge \
        -p "$sync_patch" 2>&1)" || patch_rc=$?
    if (( patch_rc != 0 )); then
        local inflight
        inflight="$(kubectl -n argocd get application "$app" \
            -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)"
        if [[ "$inflight" == "Running" ]]; then
            log_warn "sync $app: operación selfHeal EN VUELO — la adopto y espero su fase terminal"
            prev_started=""
        else
            printf '%s\n' "$patch_out" >&2
            _gate_record "sync-$app" fail 0
            return 1
        fi
    elif grep -q 'no change' <<< "$patch_out"; then
        sync_noop=true
        log_warn "sync $app: patch NO-OP ('no change' — .operation residual, H5) — se acepta el estado presente si ya es el deseado"
    fi
    local waited=0 phase started t0=$SECONDS net_refires=0 val_refires=0 wh_refires=0
    local live_sync live_health
    while :; do
        started="$(kubectl -n argocd get application "$app" \
            -o jsonpath='{.status.operationState.startedAt}' 2>/dev/null || true)"
        phase="$(kubectl -n argocd get application "$app" \
            -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)"
        # H5(i): sin operación nueva posible — no-op declarado por el
        # patch, o 30s sin cambio de startedAt — el veredicto sale
        # del ESTADO: Synced + Healthy + última operación Succeeded =
        # lo que el sync buscaba ya existe → gate PASS:
        if [[ "$sync_noop" == "true" ]] \
           || { (( waited >= 30 )) && [[ -n "$prev_started" && "$started" == "$prev_started" ]]; }; then
            if [[ "$phase" == "Succeeded" ]]; then
                live_sync="$(kubectl -n argocd get application "$app" \
                    -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
                live_health="$(kubectl -n argocd get application "$app" \
                    -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
                if [[ "$live_sync" == "Synced" && "$live_health" == "Healthy" ]]; then
                    log_ok "sync $app: sin operación nueva pero el estado deseado YA existe (Synced+Healthy+Succeeded) — H5 #15"
                    _gate_record "sync-$app" pass $(( SECONDS - t0 ))
                    return 0
                fi
            fi
        fi
        if [[ -z "$prev_started" || "$started" != "$prev_started" ]]; then
            case "$phase" in
                Succeeded) break ;;
                Failed|Error)
                    local op_msg
                    op_msg="$(kubectl -n argocd get application "$app" \
                        -o jsonpath='{.status.operationState.message}' 2>/dev/null || true)"
                    # F-A/F-D corrida #15: con errexit VIVO (fix del
                    # orquestador) un transitorio de red acá mataría
                    # la fase — si el fallo tiene firma de RED (el
                    # "server misbehaving" del DNS del teléfono tumbó
                    # el sync en vivo), se RE-DISPARA el sync y se
                    # sigue esperando dentro del timeout. TOPE de 5
                    # re-disparos (P1.11): la firma de red es amplia
                    # ("connection refused" puede ser un servicio mal
                    # configurado) — persistente ≠ transitorio, y tras
                    # el tope se reporta como fallo REAL con el msg:
                    if grep -qiE "$AEGIS_NET_SIGS" <<< "$op_msg" \
                       && (( waited < timeout && net_refires < 5 )); then
                        net_refires=$(( net_refires + 1 ))
                        log_warn "sync $app: $phase por RED transitoria — re-disparo $net_refires/5 (${waited}s/${timeout}s)"
                        prev_started="$started"
                        run_cmd kubectl -n argocd patch application "$app" \
                            --type merge -p "$sync_patch" || true
                        sleep 5; waited=$(( waited + 5 ))
                        continue
                    fi
                    # ¿la CAUSA está en el detalle por recurso? El
                    # mensaje de la App es el SÍNTOMA genérico ("tasks
                    # are not valid"); el motivo real vive en
                    # syncResult.resources[].message (A v1.1):
                    local res_msgs
                    res_msgs="$(kubectl -n argocd get application "$app" -o json 2>/dev/null \
                        | jq -r '[.status.operationState.syncResult.resources[]?.message // empty] | join(" ")' 2>/dev/null || true)"
                    # Hallazgo A v1.1 — WEBHOOK QUE NO ATIENDE: el
                    # proveedor (cert-manager, kyverno) está a medio
                    # levantar. Tarda 1-2 min desde cero: reintentos
                    # LARGOS (30/60/90/120/150s ≈ 7 min de techo),
                    # contador propio:
                    if grep -qiE "$AEGIS_WEBHOOK_NOTREADY_SIGS" <<< "$op_msg $res_msgs" \
                       && (( wh_refires < 5 )); then
                        wh_refires=$(( wh_refires + 1 ))
                        local wh_wait=$(( wh_refires * 30 ))
                        log_warn "sync $app: el ADMISSION WEBHOOK que gobierna estos recursos aún no atiende (A v1.1) — reintento $wh_refires/5 en ${wh_wait}s (un proveedor desde cero tarda 1-2 min)"
                        printf '  causa: %s\n' "$(grep -oiE "$AEGIS_WEBHOOK_NOTREADY_SIGS[^\"]*" <<< "$op_msg $res_msgs" | head -1)" >&2
                        prev_started="$started"
                        sleep "$wh_wait"; waited=$(( waited + wh_wait ))
                        run_cmd kubectl -n argocd patch application "$app" \
                            --type merge -p "$sync_patch" || true
                        sleep 5; waited=$(( waited + 5 ))
                        continue
                    fi
                    # Hallazgo A v1.0: "tasks are not valid" en el
                    # primer sync = discovery/generator que aún no
                    # convergió — transitorio CONOCIDO. Reintento con
                    # backoff (3 veces, ~10-15s: el de la corrida
                    # real validó bien segundos después). Contador
                    # PROPIO: no comparte tope con los de red:
                    if grep -qiE "$AEGIS_SYNC_VALIDATION_SIGS" <<< "$op_msg" \
                       && (( waited < timeout && val_refires < 3 )); then
                        val_refires=$(( val_refires + 1 ))
                        log_warn "sync $app: $phase por VALIDACIÓN transitoria (¿discovery sin los tipos aún? — Hallazgo A v1.0) — reintento $val_refires/3 en $(( 5 * val_refires + 5 ))s"
                        prev_started="$started"
                        sleep $(( 5 * val_refires + 5 ))
                        waited=$(( waited + 5 * val_refires + 5 ))
                        run_cmd kubectl -n argocd patch application "$app" \
                            --type merge -p "$sync_patch" || true
                        sleep 5; waited=$(( waited + 5 ))
                        continue
                    fi
                    printf '%s\n' "$op_msg" >&2
                    # al morir DE VERDAD: QUÉ tarea es inválida, no
                    # solo la frase genérica (Hallazgo A, pedido
                    # explícito) — recursos del syncResult con
                    # mensaje + conditions de la App:
                    log_error "sync $app terminó $phase — detalle de tareas/recursos:"
                    kubectl -n argocd get application "$app" -o json 2>/dev/null \
                        | jq -r '(.status.operationState.syncResult.resources[]? | select((.status? // "") != "Synced" or ((.message? // "") | test("error|invalid|failed"; "i"))) | "  \(.kind)/\(.name): \(.status // "-") — \(.message // "-")"),
                                 (.status.conditions[]? | "  cond \(.type): \(.message)")' >&2 || true
                    (( net_refires >= 5 )) && \
                        log_error "sync $app: 5 re-disparos con la MISMA firma de red — esto ya no es transitorio (¿servicio mal configurado detrás de la firma?)"
                    (( val_refires >= 3 )) && \
                        log_error "sync $app: 3 reintentos de validación agotados — los tipos/recursos de arriba NO convergen solos: manifiesto roto o CRD ausente de verdad"
                    _gate_record "sync-$app" fail $(( SECONDS - t0 ))
                    return 1 ;;
            esac
        fi
        if (( waited >= timeout )); then
            log_error "sync $app sin fase terminal NUEVA en ${timeout}s (phase=${phase:-?})"
            # H7 bonus: op previa Succeeded + timeout esperando algo
            # "nuevo" con la App OutOfSync sostenida = DRIFT
            # (defaulting/mutación), NO timing — decirlo con los
            # recursos, no dejárselo deducir al lector:
            if [[ "$phase" == "Succeeded" ]]; then
                log_error "op=Succeeded al momento del timeout — si la App está OutOfSync sostenida es DRIFT (defaulting del admission, H7), no timing; recursos no-Synced:"
                kubectl -n argocd get application "$app" -o json 2>/dev/null \
                    | jq -r '.status.resources[]? | select(.status != "Synced") | "  \(.kind)/\(.name): \(.status)"' >&2 || true
            fi
            _gate_record "sync-$app" fail $(( SECONDS - t0 ))
            return 1
        fi
        # H5(ii): evidencia periódica — 17 min de silencio fue el
        # anti-patrón del timeout mudo, otra vez, en el helper que
        # más fases usan:
        if (( waited > 0 && waited % 30 == 0 )); then
            log_info "sync $app: esperando operación nueva (${waited}s/${timeout}s) — phase=${phase:-?} startedAt=${started:-?}"
        fi
        sleep 5; waited=$(( waited + 5 ))
    done
    # espera de Healthy PROPIA (reemplaza al kubectl wait mudo):
    # evidencia cada 30s, y al agotar imprime los recursos no sanos +
    # pods y events del namespace DESTINO — la evidencia que resolvió
    # H6 en un vistazo (ImagePullBackOff visible al instante):
    local hwaited=0 health
    while :; do
        health="$(kubectl -n argocd get application "$app" \
            -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
        if [[ "$health" == "Healthy" ]]; then
            # clase G auditoría: pass Y fail quedan en gates.jsonl:
            _gate_record "sync-$app" pass $(( SECONDS - t0 ))
            return 0
        fi
        if (( hwaited >= timeout )); then
            log_error "sync $app: sin Healthy en ${timeout}s (health=${health:-?}) — recursos no sanos:"
            kubectl -n argocd get application "$app" -o json 2>/dev/null \
                | jq -r '.status.resources[]? | select((.health.status // "Healthy") != "Healthy" or .status != "Synced") | "  \(.kind)/\(.name): sync=\(.status) health=\(.health.status // "-") \(.health.message // "")"' >&2 || true
            local dest_ns
            dest_ns="$(kubectl -n argocd get application "$app" \
                -o jsonpath='{.spec.destination.namespace}' 2>/dev/null || true)"
            if [[ -n "$dest_ns" ]]; then
                kubectl -n "$dest_ns" get pods >&2 || true
                kubectl -n "$dest_ns" get events --sort-by=.lastTimestamp \
                    2>/dev/null | tail -n 10 >&2 || true
            fi
            _gate_record "sync-$app" fail $(( SECONDS - t0 ))
            return 1
        fi
        if (( hwaited > 0 && hwaited % 30 == 0 )); then
            log_info "sync $app: esperando Healthy (${hwaited}s/${timeout}s, health=${health:-?})"
        fi
        sleep 5; hwaited=$(( hwaited + 5 ))
    done
}

# ── gate reforzado para Apps de (casi) solo Secrets ─────────────────
# Corrida #4: para una App KSOPS, "Healthy" es TRIVIAL (los Secrets
# no tienen health) — el sync puede haber fallado el build entero y
# la espera de Healthy pasa igual. Este gate: (1) distingue build
# ROTO (ComparisonError de kustomize) de un ComparisonError
# TRANSITORIO de red (git fetch caído — corrida #8: jenkins-secrets
# "build roto" que pasaba al reintentar; con la red móvil del
# operador es frecuente) y de timing puro; (2) exige Synced DE
# VERDAD, con poll generoso (patrón timing #8).
# F-B corrida #15: el sync de jenkins-secrets murió por DNS
# transitorio y este gate PASÓ igual — la App estaba "Synced"… A LA
# REVISIÓN VIEJA. "Synced" sin más no prueba que lo RECIÉN pusheado
# esté aplicado. Tercer parámetro: el sha esperado (rev-parse HEAD
# post-push) — Synced cuenta solo si revision/revisions lo contiene
# (ArgoCD automated reintenta solo en su ciclo de refresh, así que
# el poll converge):
argo_secrets_gate() {   # <app> [timeout_s] [expected_sha]
    local app="$1" timeout="${2:-300}" expected="${3:-}" waited=0
    local cond msg t0=$SECONDS
    while :; do
        cond="$(kubectl -n argocd get application "$app" \
            -o jsonpath='{.status.conditions[*].type}' 2>/dev/null || true)"
        if grep -q 'ComparisonError' <<< "$cond"; then
            msg="$(kubectl -n argocd get application "$app" \
                -o jsonpath='{.status.conditions[*].message}' 2>/dev/null || true)"
            if grep -qiE 'dial tcp|i/o timeout|lookup|failed to get git|connection refused|connection reset|EOF' <<< "$msg"; then
                log_warn "$app: ComparisonError TRANSITORIO de red — esperando (${waited}s/${timeout}s)"
                # E-1 reporte in-VM #14: el DNS del entorno se ensucia
                # intermitente y el init no lo distinguía de un bug.
                # A los 60s de transitorio sostenido, el runbook §1.9
                # se imprime como PISTA (diagnóstico, no remediación
                # automática — reiniciar CoreDNS lo decide el operador):
                if (( waited == 60 )); then
                    log_warn "60s de error transitorio sostenido — runbook DNS (§1.9): en el host 'ip route' + 'resolvectl status' (¿ruta/nameserver fantasma?); si el CLUSTER no resuelve: 'kubectl -n kube-system rollout restart deploy/coredns'"
                fi
            else
                printf '%s\n' "$msg" >&2
                _gate_record "$app-synced" fail $(( SECONDS - t0 ))
                die "$app: build de kustomize ROTO (¿entry/resource sin archivo? — regla temporal del generator)"
            fi
        elif kubectl -n argocd get application "$app" \
               -o jsonpath='{.status.sync.status}' 2>/dev/null | grep -qx Synced; then
            if [[ -n "$expected" ]]; then
                local revs
                revs="$(kubectl -n argocd get application "$app" \
                    -o jsonpath='{.status.sync.revision} {.status.sync.revisions}' \
                    2>/dev/null || true)"
                if ! grep -q "$expected" <<< "$revs"; then
                    # forma if (no `(( )) &&`): con errexit VIVO
                    # (F-A) un statement que retorna 1 mata la fase:
                    if (( waited % 30 == 0 )); then
                        log_warn "$app: Synced pero a una revisión VIEJA — esperando ${expected:0:8} (${waited}s/${timeout}s)"
                    fi
                    sleep 5; waited=$(( waited + 5 ))
                    if (( waited >= timeout )); then
                        printf 'revisión viva: %s / esperada: %s\n' "$revs" "$expected" >&2
                        _gate_record "$app-synced" fail $(( SECONDS - t0 ))
                        die "GATE $app-synced FALLÓ — nunca llegó a la revisión pusheada (F-B #15)"
                    fi
                    continue
                fi
            fi
            _gate_record "$app-synced" pass $(( SECONDS - t0 ))
            log_ok "GATE $app-synced"
            return 0
        fi
        if (( waited >= timeout )); then
            # H7 corrida #13: el error del apply reintentado vive en
            # operationState y el timeout moría MUDO — mostrarlo:
            kubectl -n argocd get application "$app" \
                -o jsonpath='{.status.operationState.message}' >&2 || true
            echo >&2
            # H7 corrida #15: op Succeeded + OutOfSync sostenido =
            # SIEMPRE drift (defaulting del admission — Kyverno
            # inyecta campos al admitir), no timing. Decirlo con los
            # recursos culpables en vez de dejar la deducción al
            # lector del log:
            local end_phase
            end_phase="$(kubectl -n argocd get application "$app" \
                -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)"
            if [[ "$end_phase" == "Succeeded" ]]; then
                log_error "op=Succeeded y sigue sin Synced: esto es DRIFT (defaulting/mutación del admission — H7 #15), no timing. Recursos no-Synced (revisar ignoreDifferences de la App):"
                kubectl -n argocd get application "$app" -o json 2>/dev/null \
                    | jq -r '.status.resources[]? | select(.status != "Synced") | "  \(.kind)/\(.name): \(.status)"' >&2 || true
            fi
            _gate_record "$app-synced" fail $(( SECONDS - t0 ))
            die "GATE $app-synced FALLÓ — no convergió en ${timeout}s (arriba: operationState.message y diagnóstico)"
        fi
        # H5(ii) #15: el camino "todavía no Synced, sin error" era el
        # único MUDO de este gate — evidencia periódica:
        if (( waited > 0 && waited % 30 == 0 )); then
            log_info "$app: esperando Synced (${waited}s/${timeout}s)"
        fi
        sleep 5; waited=$(( waited + 5 ))
    done
}

# ── ansible: become sin fricción ni timeout ─────────────────────────
# Corrida #4: --ask-become-pass por playbook = DOS prompts en fase 20
# y "Timed out waiting for become success" si el operador tarda.
#
# Corrida #6, BUG 1 — el fallback --become-password-file NO se honró
# en vivo: el detector cayó bien al camino del archivo, el operador
# tipeó el password, y AMBOS playbooks murieron con "Timed out waiting
# for become success or become password prompt" — ansible ignoró el
# archivo y esperó un prompt interactivo. La flag estaba "verificada
# contra el source de ansible-core 2.21" pero NO probada en vivo: la
# misma clase verificado-vs-fuente≠probado que los permission groups
# de CF. El binario decidió, no el source. Se destrabó con NOPASSWD.
#
# DECISIÓN: NO reintentar el flag no-probado. Cuando NO hay NOPASSWD,
# el init ENCAMINA al ÚNICO camino probado en vivo — instala un drop-in
# NOPASSWD (validado con visudo, freno ROJO, reversible con rm) y corre
# ansible no interactivo. El password va SOLO al stdin de sudo -S
# (jamás argv, jamás archivo persistente). ANSIBLE_BECOME_ARGS queda
# vacío a propósito: become escala por NOPASSWD, no por flag.
# DEUDA ABIERTA (VALIDACION §4.x): reproducir por qué ansible-core
# ignora --become-password-file en este setup (local conn + become).
# NO se afirma resuelto — se rodea con el camino probado.
# Uso:  ansible_become_setup
#       ansible-playbook ... "${ANSIBLE_BECOME_ARGS[@]}"
declare -a ANSIBLE_BECOME_ARGS=()
ansible_become_setup() {
    ANSIBLE_BECOME_ARGS=()
    # sudo -K PRIMERO (corrida #5, hallazgo 0): `sudo -n true` da
    # FALSO POSITIVO si hay timestamp cacheado de un sudo anterior
    # (la fase 05 lo deja cebado) — el init creyó NOPASSWD, ansible
    # (otra sesión, sin cache) pidió password y murió por timeout.
    # -K mata el cache: -n solo pasa con NOPASSWD REAL en sudoers:
    sudo -K 2>/dev/null || true
    if sudo -n true 2>/dev/null; then
        log_info "sudo sin password (NOPASSWD real, cache purgado) — become no interactivo"
        return 0
    fi
    : "${SECRETS_TMP:?ansible_become_setup requiere secrets_workdir antes}"
    # P0.4 auditoría: en --non-interactive no hay a quién pedirle el
    # password — y esto se descubría a ~30 min de corrida. El doctor
    # de la fase 00 ya lo detecta temprano; este die es la red final:
    ni_mode && die "sudo sin NOPASSWD en --non-interactive — instalar el drop-in ANTES de correr: printf '%s ALL=(ALL) NOPASSWD:ALL\\n' \"\$(id -un)\" | sudo tee /etc/sudoers.d/010-aegis-init-nopasswd && sudo chmod 0440 /etc/sudoers.d/010-aegis-init-nopasswd"
    log_warn "sudo sin NOPASSWD — se habilitará NOPASSWD para el usuario (el fallback por archivo de become NO funcionó en la corrida #6; NOPASSWD es el único camino probado)"
    gate_red "habilitar sudo NOPASSWD para $(id -un) en ESTE host (drop-in en /etc/sudoers.d — reversible: 'sudo rm /etc/sudoers.d/010-aegis-init-nopasswd'). En VM greenfield DESECHABLE es lo esperado; si esto es un host REAL, ABORTÁ y configurá sudoers a mano"
    local _pw f_dropin
    read -rsp "password de sudo (UNA vez; solo va al stdin de sudo, nunca a argv ni a archivo): " _pw \
        || die "stdin cerrado pidiendo el password de sudo — configurar NOPASSWD y --non-interactive"
    echo >&2
    f_dropin="$SECRETS_TMP/aegis-nopasswd"
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$(id -un)" > "$f_dropin"
    chmod 0440 "$f_dropin"
    # validar sintaxis ANTES de instalar (un sudoers roto rompe sudo);
    # este sudo -S es ADEMÁS el self-test del password: si es incorrecto
    # muere ACÁ en segundos, no en un timeout de 60s a mitad del playbook:
    if ! printf '%s' "$_pw" | sudo -S -k -p '' visudo -cf "$f_dropin" >/dev/null 2>&1; then
        unset _pw
        die "sudo -S falló (¿password incorrecto?) o el drop-in no valida — /etc/sudoers.d intacto"
    fi
    printf '%s' "$_pw" | sudo -S -k -p '' install -m 0440 -o root -g root \
        "$f_dropin" /etc/sudoers.d/010-aegis-init-nopasswd \
        || { unset _pw; die "no pude instalar el drop-in NOPASSWD en /etc/sudoers.d"; }
    unset _pw
    # la copia tmpfs quedó 0440 y el shred del cleanup no podía
    # sobreescribirla ("Permission denied" cosmético, visto #15) —
    # el instalado en /etc/sudoers.d conserva su 0440:
    chmod u+w "$f_dropin" 2>/dev/null || true
    sudo -K 2>/dev/null || true
    gate "nopasswd-activo" bash -c "sudo -n true 2>/dev/null"
    log_ok "NOPASSWD activo — ansible corre no interactivo por el camino probado (become sin flag)"
}

# ── estado dual git del repo de plataforma (CR-6 reporte in-VM #14) ─
# $PLATFORM_DIR es un working clone que el init muta y pushea — pero
# NADA garantizaba que estuviera al día al arrancar una fase. El
# flujo REAL de la #14: el operador arregla a mano en GitHub (u otro
# clone) → retoma el init → este clone quedó DETRÁS → el siguiente
# push pisa el fix o choca. Toda fase que muta el repo ARRANCA
# sincronizando: ff-only trae lo remoto; si divergió (commits
# locales sin pushear Y remotos nuevos a la vez) el init NO decide
# solo — muere con el estado visible para que el operador reconcilie:
platform_repo_sync() {
    if ! git -C "$PLATFORM_DIR" rev-parse --abbrev-ref '@{upstream}' \
         >/dev/null 2>&1; then
        log_info "platform sin upstream todavía (pre-fase-12) — sync omitido"
        return 0
    fi
    run_cmd retry_net 3 git -C "$PLATFORM_DIR" fetch origin || \
        die "fetch de plataforma falló — red o deploy key; re-correr la fase"
    if run_cmd git -C "$PLATFORM_DIR" merge --ff-only '@{upstream}'; then
        log_info "platform al día con el remoto (ff-only)"
        return 0
    fi
    git -C "$PLATFORM_DIR" status -sb >&2 || true
    git -C "$PLATFORM_DIR" log --oneline -3 '@{upstream}' >&2 || true
    # P3 auditoría: "DIVERGIÓ" era el diagnóstico también cuando el
    # merge fallaba por WORKING TREE SUCIO (fase anterior muerta a
    # mitad, pre-commit) — remediación distinta, mensaje distinto:
    if [[ -n "$(git -C "$PLATFORM_DIR" status --porcelain 2>/dev/null)" ]]; then
        die "el merge falló con el working tree SUCIO (arriba: status) — una fase anterior murió entre mutar y commitear; revisar los cambios en $PLATFORM_DIR (commitear o descartar) y re-correr la fase"
    fi
    die "el clone de plataforma DIVERGIÓ del remoto (commits locales Y remotos a la vez) — reconciliar a mano en $PLATFORM_DIR y re-correr la fase"
}

# ── commit SOLO si hay cambios (clase F auditoría 2026-07-18) ───────
# `git commit || true` vivía en 6 fases: el || true existía para el
# re-run sin cambios, pero tragaba también los fallos REALES (hook,
# identidad, index.lock) → el push "exitoso" no llevaba nada y ArgoCD
# jamás veía el cambio (el síntoma aparecía 2 fases después). La
# distinción correcta es ESTRUCTURAL: staged vacío = no-op legítimo;
# staged con cambios = el commit DEBE salir bien (errexit lo mata si
# no). Uso: git_commit_if_changes <dir> <msg> [paths-a-agregar...]
# (sin paths = add -A).
git_commit_if_changes() {
    local dir="$1" msg="$2"; shift 2
    if (($#)); then
        run_cmd git -C "$dir" add -- "$@"
    else
        run_cmd git -C "$dir" add -A
    fi
    if git -C "$dir" diff --cached --quiet; then
        log_info "nada que commitear (re-run idempotente)"
        return 0
    fi
    run_cmd git -C "$dir" commit -m "$msg" --no-verify
}

# ── git push SIEMPRE verificado (corrida #9) ────────────────────────
# Un push fallido que "sigue de largo" deja un commit local sin
# pushear → ArgoCD no ve el archivo → kustomize roto UNA FASE después
# (el error de kustomize es el síntoma; la causa es el push no
# verificado). retry_net absorbe el corte transitorio de la red móvil;
# si igual falla, die con la causa REAL y la fase para retomar:
git_push_verified() {   # <repo_dir> [args extra de push...]
    local dir="$1"; shift
    run_cmd retry_net 3 git -C "$dir" push "$@" || \
        die "git push falló en $dir — commit local SIN pushear (ArgoCD leería un repo viejo); verificar red/deploy key y re-correr la fase"
}

# ── rollouts TOLERANTES a red lenta (fases 20/40 — E-1) ─────────────
# La firma del operador: "la 20/40 se cae, la re-tiro sin cambiar
# nada y funciona". Causa: el primer boot pullea imágenes de
# docker.io por la red móvil y un `rollout status --timeout=120s`
# convierte LENTO en FALLO — el re-run "funciona" solo porque el
# pull siguió en background y quedó cacheado. Con red móvil,
# ImagePullBackOff transitorio es NORMAL (el kubelet reintenta con
# backoff solo). Espera GENEROSA + evidencia periódica: lento nunca
# es mudo, y el timeout final muere con el estado real:
wait_rollout() {   # <ns> <kind/name> [timeout_s=900] [every_s=20]
    local ns="$1" obj="$2" timeout="${3:-900}" every="${4:-20}" waited=0
    until kubectl -n "$ns" rollout status "$obj" --timeout=5s \
            >/dev/null 2>&1; do
        if (( waited >= timeout )); then
            log_error "rollout $ns/$obj sin converger en ${timeout}s — estado real:"
            kubectl -n "$ns" get pods >&2 || true
            kubectl -n "$ns" get events --sort-by=.lastTimestamp \
                2>/dev/null | tail -n 8 >&2 || true
            return 1
        fi
        local notready
        notready="$(kubectl -n "$ns" get pods --no-headers 2>/dev/null \
                    | grep -vE 'Running|Completed' | head -n 3 || true)"
        log_info "esperando $ns/$obj (${waited}s/${timeout}s)${notready:+ — $(echo "$notready" | tr '\n' ' ')}"
        sleep "$every"; waited=$(( waited + every ))
    done
}

# ── CONVERGENCIA ANTES DE MEDIR (la familia nº1 del init) ───────────
# Cinco instancias del MISMO bug en cinco disfraces: coredns
# inexistente (H4), operación de sync que nunca llega (H5),
# Succeeded viejo leído como nuevo (bug C), sync contra un discovery
# sin los tipos (A v1.0), gate midiendo en plena cascada de
# ReplicaSets (B v1.0). La regla, canonizada acá:
#   EXISTENCIA → ESTABILIDAD → recién entonces MEDIR.
# Todo gate que mide el efecto de una acción asíncrona pasa por
# estos helpers — parche puntual nuevo de esta clase = FAIL de
# revisión, no de corrida.

# wait_for <timeout_s> <every_s> <qué-espero> <cmd...>
#   El primitivo: poll con EVIDENCIA periódica (cada ~30s dice qué
#   está esperando) y timeout que nombra lo que no llegó. Para
#   condiciones puntuales; para workloads usar k8s_converged.
wait_for() {
    local timeout="$1" every="$2" what="$3"; shift 3
    local t0=$SECONDS last_log=0
    until "$@"; do
        if (( SECONDS - t0 >= timeout )); then
            log_error "esperando '$what': no llegó en ${timeout}s"
            return 1
        fi
        if (( SECONDS - t0 - last_log >= 30 )); then
            last_log=$(( SECONDS - t0 ))
            log_info "esperando '$what' ($(( SECONDS - t0 ))s/${timeout}s)"
        fi
        sleep "$every"
    done
}

# k8s_converged <ns> <kind/name> [timeout=300]
#   EXISTENCIA (el objeto puede no estar creado aún — H4/A) →
#   ESTABILIDAD (rollout status: generación observada + réplicas al
#   día — B: un restart + la mutación de Kyverno encadenan DOS
#   despliegues y en la ventana conviven 3+ ReplicaSets). El caller
#   mide DESPUÉS de que esto retorne 0.
k8s_converged() {
    local ns="$1" obj="$2" timeout="${3:-300}"
    # bash -c: la redirección es DEL PROBE, no de wait_for (si no,
    # se tragaría la evidencia periódica del propio helper):
    wait_for "$timeout" 3 "existencia de $ns/$obj" \
        bash -c "kubectl -n '$ns' get '$obj' -o name >/dev/null 2>&1" || return 1
    wait_rollout "$ns" "$obj" "$timeout"
}

# deploy_current_pods_ok <ns> <deploy> <jq-filtro-por-pod>
#   Mide SOLO los pods del ReplicaSet VIGENTE del deployment (por
#   pod-template-hash del RS de mayor revision con replicas>0) — en
#   una cascada de despliegues "los pods del namespace" incluyen
#   SIEMPRE pods viejos muriendo (B v1.0). Exige >=1 pod y que TODOS
#   los del RS vigente cumplan el filtro jq (sobre el objeto pod):
deploy_current_pods_ok() {
    local ns="$1" deploy="$2" jqf="$3" hash
    hash="$(kubectl -n "$ns" get rs -o json 2>/dev/null | jq -r --arg d "$deploy" '
        [.items[] | select((.metadata.ownerReferences[]? | select(.kind=="Deployment" and .name==$d)) != null)
                  | select((.spec.replicas // 0) > 0)]
        | max_by(.metadata.annotations["deployment.kubernetes.io/revision"] | tonumber)
        | .metadata.labels["pod-template-hash"] // empty')"
    [[ -n "$hash" ]] || { log_error "sin ReplicaSet vigente para $ns/$deploy"; return 1; }
    kubectl -n "$ns" get pods -l "pod-template-hash=$hash" -o json 2>/dev/null \
        | jq -e "[.items[] | select(.metadata.deletionTimestamp == null)] | length > 0 and all(${jqf})" >/dev/null
}

# webhook_serving <ns> <svc> [timeout=300]
#   Hallazgo A v1.1 — la instancia nº6 de la familia, y la más
#   engañosa: una App que PROVEE un admission webhook está "Synced +
#   Healthy" ANTES de que su webhook atienda. En esa ventana, todo
#   apply de un recurso gobernado por ese webhook muere con "failed
#   calling webhook ...: no endpoints available for service" — y el
#   error NO es del recurso, es del proveedor a medio levantar.
#   La señal REAL no es el health de la App ni el rollout del
#   deployment: son los ENDPOINTS del Service (addresses no vacío =
#   hay pods listos detrás). Se espera ESO antes de sincronizar
#   cualquier App que cree recursos de ese dominio:
webhook_serving() {   # <ns> <svc> [timeout]
    local ns="$1" svc="$2" timeout="${3:-300}"
    wait_for "$timeout" 3 "existencia del Service $ns/$svc (webhook)" \
        bash -c "kubectl -n '$ns' get svc '$svc' -o name >/dev/null 2>&1" || return 1
    if ! wait_for "$timeout" 3 "ENDPOINTS del webhook $ns/$svc (Healthy de la App NO alcanza)" \
        bash -c "[[ -n \"\$(kubectl -n '$ns' get endpoints '$svc' -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)\" ]]"; then
        log_error "el webhook $ns/$svc no tiene endpoints — pods del ns:"
        kubectl -n "$ns" get pods >&2 || true
        return 1
    fi
    log_ok "webhook $ns/$svc SIRVIENDO (endpoints presentes)"
}

# ── probes con kubectl run: reset ANTES de cada intento ─────────────
# P1.8 auditoría: `kubectl run --rm` + retry se AUTO-ANULA — si el
# attach vence (red lenta), el pod queda vivo y TODOS los reintentos
# mueren con AlreadyExists, exactamente en el escenario para el que
# el retry existe. Todo probe reintentable borra su pod primero:
probe_reset() {   # <ns> <pod-name>
    kubectl -n "$1" delete pod "$2" --ignore-not-found --now \
        >/dev/null 2>&1 || true
}

# ── firmas de error de RED transitoria (E-1, un solo lugar) ─────────
# Las consumen argo_sync (re-dispara el sync), argo_secrets_gate
# (espera en vez de morir) y jenkins_build_retry (re-dispara el
# build). "server misbehaving" = el upstream DNS del teléfono del
# operador, visto EN VIVO #15 tumbando el sync y (probable) el build:
AEGIS_NET_SIGS='dial tcp|i/o timeout|TLS handshake timeout|server misbehaving|connection reset|connection refused|temporary failure|could not resolve|unexpected EOF|lookup .* on|failed to get git'

# firmas de VALIDACIÓN transitoria de un sync (Hallazgo A v1.0): el
# primer sync tras crear/actualizar la root App puede correr contra
# un discovery del API server que aún no registró los tipos que la
# App aplica (la root estaba desplegando CRDs 12s antes) o contra un
# generator a medio materializar → "one or more synchronization
# tasks are not valid" / "no matches for kind". Mismo input, 4 min
# después: Synced en 7s. Es la familia convergencia (instancia #4):
AEGIS_SYNC_VALIDATION_SIGS='tasks are not valid|not valid|no matches for kind|could not find the requested resource|conversion webhook.* (failed|denied|unavailable)|failed to sync cluster.*cache'

# firmas de WEBHOOK QUE AÚN NO ATIENDE (Hallazgo A v1.1, el texto
# REAL de la corrida): "failed calling webhook
# webhook.cert-manager.io: no endpoints available for service
# cert-manager-webhook". El mensaje de arriba de la App decía "tasks
# are not valid" (matcheaba), pero el detalle por recurso —el que
# dice la CAUSA— no matcheaba ninguna firma: se clasificaba por el
# síntoma, no por la causa. Y el tiempo importa: un proveedor de
# webhook desde cero tarda 1-2 min, así que ESTA clase lleva
# reintentos MÁS LARGOS que el resto (el 3×10s de la sesión pasada
# era insuficiente — dicho por el operador con evidencia):
AEGIS_WEBHOOK_NOTREADY_SIGS='failed calling webhook|no endpoints available|webhook.*(connection refused|context deadline exceeded)|x509.*webhook'

# ── red vs config ───────────────────────────────────────────────────
# retry_net: los gates con egress reintentan antes de diagnosticar
# (lección red-vs-config: primero descartar corte de red).
retry_net() {
    local tries="$1"; shift
    # P1.11 auditoría: 3×5s fijos = 15s totales frente a cortes de la
    # red móvil que duran MINUTOS — el retry existía pero no cubría el
    # corte real. Backoff exponencial capado (5/15/45/90/90…): con
    # tries=3 cubre ~1 min; con tries=6, ~5.5 min. El delay se loguea
    # para que la espera nunca sea muda:
    local i delay=5
    for ((i = 1; i <= tries; i++)); do
        "$@" && return 0
        (( i == tries )) && break
        # H4 corrida #15 (UX): el "(¿red?)" fijo etiquetaba mal
        # errores que NO eran de red (NotFound de una carrera de
        # creación) — el wrapper no ve el stderr del comando, así que
        # no AFIRMA la causa: apunta al error de arriba y da el mapa:
        log_warn "intento $i/$tries falló — reintento en ${delay}s (la causa está en el error de ARRIBA: timeout/DNS=red transitoria; NotFound=carrera de creación; otra cosa=probablemente real)"
        sleep "$delay"
        delay=$(( delay * 3 )); (( delay > 90 )) && delay=90
    done
    return 1
}

# ══ la CLI: invocar a otro comando, y la ayuda ═══════════════════════
# (03 §1/§2/§5 — las dos funciones que faltaban en v2)

# aegis_exec <comando> [args...] — la regla 5.1 hecha función.
#
# El bug que la justifica tiene línea y fecha: aegis-check:766,785
# invocaba a aegis-edge y aegis-webhook por ruta relativa, y el `case`
# que clasificaba la salida no tenía rama para 127. Con el comando
# ausente —renombrado, movido, sin permisos— la ronda no decía «no pude
# mirar»: decía «sin fallos». Verde por ceguera es el peor desenlace
# que puede dar una herramienta de vigilancia, porque nadie investiga
# un verde.
#
# Acá 126 y 127 son rc 2 CON el motivo, nunca 0 y nunca 1.
aegis_exec() {
    local cmd="$1"; shift
    local destino="$AEGIS_ROOT/libexec/aegis-$cmd"
    if [[ ! -e "$destino" ]]; then
        printf 'NO SE PUDO EVALUAR: el comando %s no existe (%s) — no es que no haya fallos: es que no se pudo mirar\n' \
            "${AEGIS_CMD:-aegis} $cmd" "$destino" >&2
        return 2
    fi
    if [[ ! -x "$destino" ]]; then
        printf 'NO SE PUDO EVALUAR: %s existe pero no es ejecutable (chmod +x)\n' "$destino" >&2
        return 2
    fi
    "$destino" "$@"
    local rc=$?
    if [[ $rc == 126 || $rc == 127 ]]; then
        printf 'NO SE PUDO EVALUAR: %s no se pudo ejecutar (rc %s: ¿falta el intérprete del shebang?)\n' \
            "${AEGIS_CMD:-aegis} $cmd" "$rc" >&2
        return 2
    fi
    return $rc
}

# cli_help — imprime el bloque `# aegis-help:` del archivo que llama,
# más la tabla de códigos de salida. La tabla NO se escribe acá: vive
# en share/codigos-de-salida.txt y la lee también lib/aegis/
# desenlaces.py, para que bash y python no puedan discrepar sobre lo
# que significa un 2.
cli_help() {
    local archivo="${1:-${BASH_SOURCE[1]}}"
    sed -n '/^# aegis-help:/,/^[^#]/p' "$archivo" | sed '1d;$d;s/^# \?//'
    echo
    cat "$AEGIS_ROOT/share/codigos-de-salida.txt"
}
