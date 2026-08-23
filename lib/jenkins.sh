#!/usr/bin/env bash
# aegis-init lib/jenkins.sh — acceso a la API de Jenkins DENTRO del
# pod (server.insecure detrás del edge: siempre http://localhost).
# Regla A27 completa: el password no toca argv LOCAL ni REMOTO —
# viaja por stdin del exec hasta un netrc temporal (600) en el pod
# que se borra al salir. Crumb CSRF para los POST (crumb + cookie
# de sesión: el crumb solo vale con la sesión que lo emitió).
# Consumidores: fases 50 (ci-images), 60 (primer build), 70
# (anti-loop wfapi), 80 (build firmado).

set -euo pipefail

# _jenkins_pass_file: password de jenkins-admin a un archivo tmpfs.
# Prefiere el generado en ESTA corrida (fase 50); si no está (corrida
# --from posterior), lo lee del cluster — mecánica sin mostrarlo.
_jenkins_pass_file() {
    local f="$SECRETS_TMP/jenkins_admin_pass"
    if [[ ! -s "$f" ]]; then
        # umask 077 (P2 auditoría 2026-07-18): la redirección creaba
        # el archivo 644 y el chmod llegaba DESPUÉS — ventana de
        # lectura. El subshell acota el umask a esta escritura:
        ( umask 077
          kubectl -n jenkins-system get secret jenkins-admin \
              -o jsonpath='{.data.password}' | base64 -d > "$f" )
        chmod 600 "$f"
    fi
    printf '%s' "$f"
}

# _jenkins_netrc_stdin: emite el netrc por stdout (para pipear al
# exec). machine=localhost porque curl corre DENTRO del pod.
_jenkins_netrc_stdin() {
    local pf; pf="$(_jenkins_pass_file)"
    printf 'machine localhost login admin password '
    cat "$pf"
    printf '\n'
}

# jenkins_get <path> — GET autenticado; imprime el body.
#   ej: jenkins_get /job/ci-images/lastBuild/api/json
# P1.7 auditoría 2026-07-18: los curls in-pod no tenían --max-time y
# el kubectl exec no tenía timeout — un socket colgado (red del
# operador, pod a medio morir) colgaba la fase INDEFINIDO, peor que
# un timeout porque no deja diagnóstico. 60s de curl (consoleText
# puede ser grande) + 90s de tope duro al exec:
jenkins_get() {
    local path="$1"
    _jenkins_netrc_stdin | \
    timeout 90 kubectl -n jenkins-system exec -i sts/jenkins -c jenkins -- \
        bash -c 'umask 077; N="$(mktemp)"; cat > "$N"
                 curl -fsS --max-time 60 --netrc-file "$N" "http://localhost:8080$1"
                 rc=$?
                 rm -f "$N"
                 exit $rc' _ "$path"
}

# jenkins_get_code <path> — SOLO el http_code (sin -f: un 404 no es
# error acá — lo necesita jenkins_wait_build para distinguir "el
# build aún no existe" de "la API está rota" — P1.6):
jenkins_get_code() {
    local path="$1"
    _jenkins_netrc_stdin | \
    timeout 90 kubectl -n jenkins-system exec -i sts/jenkins -c jenkins -- \
        bash -c 'umask 077; N="$(mktemp)"; cat > "$N"
                 curl -sS --max-time 60 -o /dev/null -w "%{http_code}" \
                      --netrc-file "$N" "http://localhost:8080$1"
                 rc=$?
                 rm -f "$N"
                 exit $rc' _ "$path"
}

# jenkins_post <path> — POST autenticado con crumb CSRF.
#   ej: jenkins_post /job/ci-images/build
jenkins_post() {
    local path="$1"
    _jenkins_netrc_stdin | \
    timeout 90 kubectl -n jenkins-system exec -i sts/jenkins -c jenkins -- \
        bash -c 'umask 077; N="$(mktemp)"; J="$(mktemp)"; cat > "$N"
                 CRUMB="$(curl -fsS --max-time 30 --netrc-file "$N" -c "$J" \
                   "http://localhost:8080/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)")"
                 curl -fsS --max-time 60 --netrc-file "$N" -b "$J" -H "$CRUMB" \
                   -X POST "http://localhost:8080$1"
                 rc=$?
                 rm -f "$N" "$J"
                 exit $rc' _ "$path"
}

# jenkins_next_build <job> — el número que tendrá el PRÓXIMO build.
# Capturarlo ANTES de disparar (POST /build o push que dispara el
# webhook) y esperar a ESE build. Corrida #9: tras el disparo,
# Jenkins tarda ~5-10s en promover el build nuevo a lastBuild; en
# esa ventana lastBuild = el ANTERIOR — un FAILURE viejo cortaba el
# gate en 1s mientras el build nuevo corría hacia SUCCESS. La misma
# clase que el bug C del App self: leer el estado de la operación
# EQUIVOCADA.
# P1.6 auditoría 2026-07-18: sin retry ni validación, un transitorio
# devolvía "" o "null" y el caller esperaba un build FANTASMA hasta
# el timeout (1800s). retry_net + shape-check ^[0-9]+$ — inválido
# tras los reintentos = fallo explícito ACÁ (errexit lo hace fatal
# en la asignación del caller):
_jenkins_next_raw() {   # imprime el número SOLO si valida (un intento
    local out             # fallido no contamina el $() del caller):
    out="$(jenkins_get "/job/$1/api/json" 2>/dev/null \
           | jq -r '.nextBuildNumber // empty')" || return 1
    [[ "$out" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "$out"
}
jenkins_next_build() {
    local job="$1" n=""
    if ! n="$(retry_net 3 _jenkins_next_raw "$job")"; then
        log_error "jenkins_next_build $job: sin nextBuildNumber válido tras 3 intentos — API de Jenkins caída o job inexistente"
        return 1
    fi
    printf '%s' "$n"
}

# _jenkins_quota_stall <ventana_s> — bug corrida #11: con la
# ResourceQuota agotada el plugin kubernetes NO puede crear el pod
# del build → el build queda encolado PARA SIEMPRE y el wait esperaba
# en SILENCIO hasta el timeout (el operador diagnosticó a mano contra
# los logs del controller: "exceeded quota: jenkins-quota"). La
# evidencia vive ahí — se detecta y se REPORTA con el uso real de la
# RQ y los pods vivos (huérfanos/solapados consumen quota). Solo
# números y nombres de pods: cero material sensible. Devuelve 0 si
# detectó el stall (para que el caller pueda contarlo), 1 si no.
_jenkins_quota_stall() {
    local window="${1:-60}"
    kubectl -n jenkins-system logs sts/jenkins -c jenkins \
        --since="${window}s" 2>/dev/null | grep -m1 'exceeded quota' >&2 \
        || return 1
    log_warn "Jenkins NO puede crear el pod del build: ResourceQuota agotada (línea de arriba = evidencia del controller)"
    kubectl -n jenkins-system get resourcequota jenkins-quota >&2 || true
    log_warn "pods vivos del ns (huérfanos/solapados consumen quota; limpiarlos la libera):"
    kubectl -n jenkins-system get pods --no-headers >&2 || true
    return 0
}

# jenkins_wait_build <job> <timeout_s> <build_n> — espera SUCCESS
# del build ESPECÍFICO build_n (obligatorio: capturado con
# jenkins_next_build ANTES del disparo). Un GET 404 = el build aún
# no arrancó (webhook/quiet period asíncronos) = RUNNING, no error.
# Falla rápido si terminó FAILURE/ABORTED (fallo real ≠
# no-arrancó-todavía). Y si el build "no arranca" porque la RQ
# rechaza el pod, lo DICE en cada vuelta (corrida #11) en vez de
# esperar mudo.
jenkins_wait_build() {
    local job="$1" timeout="${2:-1200}" build="${3:?jenkins_wait_build requiere build_n (jenkins_next_build ANTES del disparo — carrera lastBuild #9)}"
    local waited=0 every=20 result api_errs=0
    while :; do
        # P1.6 auditoría 2026-07-18: TODO error del GET se mapeaba a
        # "RUNNING" — un 401 (creds), un pod caído o un exec colgado
        # esperaban el timeout COMPLETO en silencio. Solo el 404 es
        # "aún no arrancó" legítimo; cualquier otro error sostenido
        # (6 vueltas ≈ 2 min) corta con el código a la vista:
        if result="$(jenkins_get "/job/$job/$build/api/json" 2>/dev/null \
                     | jq -r '.result // "RUNNING"')" && [[ -n "$result" ]]; then
            api_errs=0
        else
            local code
            code="$(jenkins_get_code "/job/$job/$build/api/json" 2>/dev/null || echo 000)"
            if [[ "$code" == "404" ]]; then
                api_errs=0
                result=RUNNING   # el webhook/quiet period aún no lo creó
            else
                api_errs=$(( api_errs + 1 ))
                log_warn "API de Jenkins no responde el build $job#$build (http=$code, $api_errs/6)"
                if (( api_errs >= 6 )); then
                    log_error "la API de Jenkins lleva ~2 min sin responder (último http=$code) — esto NO es un build lento, es Jenkins/creds/exec roto"
                    kubectl -n jenkins-system get pods >&2 || true
                    return 1
                fi
                result=RUNNING
            fi
        fi
        case "$result" in
            SUCCESS) log_ok "build $job#$build: SUCCESS"; return 0 ;;
            FAILURE|ABORTED|UNSTABLE)
                # F-C corrida #15 (H7 aplicado a los builds): dos
                # FAILURE seguidos sin UNA línea del console — la
                # causa vive ahí y el operador la excavaba a mano:
                log_error "build $job#$build terminó $result — cola del console:"
                jenkins_get "/job/$job/$build/consoleText" 2>/dev/null \
                    | tail -n 30 >&2 || true
                return 1 ;;
        esac
        (( waited >= timeout )) && {
            log_error "build $job#$build: timeout ${timeout}s (estado: $result)"
            jenkins_get "/job/$job/$build/consoleText" 2>/dev/null \
                | tail -n 15 >&2 || true
            _jenkins_quota_stall "$timeout" || true
            return 1; }
        _jenkins_quota_stall "$every" || true
        sleep "$every"; waited=$(( waited + every ))
    done
}

# jenkins_build_retry <job> [timeout_s] [tries] — dispara el build
# por API y espera; F-D corrida #15: con la red móvil del operador
# el build puede morir por un transitorio (el "server misbehaving"
# del DNS upstream tumbó el sync de ArgoCD EN EL MISMO MINUTO que el
# build #1). Si el FAILURE tiene firma de RED en el console
# (AEGIS_NET_SIGS, common.sh) se RE-DISPARA — cada reintento manual
# costaba una corrida entera de la fase. FAILURE sin firma de red =
# fallo REAL → corta YA (el console ya quedó impreso por
# jenkins_wait_build). Captura next ANTES del POST (carrera #9):
jenkins_build_retry() {
    local job="$1" timeout="${2:-1800}" tries="${3:-3}" i next
    for ((i = 1; i <= tries; i++)); do
        next="$(jenkins_next_build "$job")"
        jenkins_post "/job/$job/build" >/dev/null
        if jenkins_wait_build "$job" "$timeout" "$next"; then
            return 0
        fi
        if jenkins_get "/job/$job/$next/consoleText" 2>/dev/null \
             | grep -qiE "$AEGIS_NET_SIGS"; then
            log_warn "build $job#$next: FAILURE con firma de RED transitoria (intento $i/$tries) — re-disparo"
            continue
        fi
        log_error "build $job#$next: FAILURE SIN firma de red — fallo real, no se reintenta (console arriba)"
        return 1
    done
    log_error "build $job: $tries intentos con fallos de red — la red no da para el build; reintentar cuando estabilice"
    return 1
}
