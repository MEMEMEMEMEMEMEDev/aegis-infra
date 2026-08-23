#!/usr/bin/env bash
# FASE 60 — webhook GitHub App → Jenkins, end-to-end. La App y el
# HMAC ya existen (fase 15); el receptor bootea en la 50 con los
# Secrets YA en el cluster (orden verificado: jenkins-secrets sync +
# gate ANTES del sts — el plugin carga el HMAC al boot, lección #12).
#
# REESCRITA post-#14 (Patrón B del reporte in-VM, en su peor forma):
# el gate único push→build acoplaba CUATRO eslabones — edge,
# delivery+HMAC, scan, build — y al fallar moría MUDO con el
# diagnóstico en un comentario (mención ≠ uso, H7). Historia de esta
# fase: #10 HMAC desincronizado (hook sobreviviente), #11 hook
# borrado por diagnóstico erróneo + quota, #12 HMAC con \n. Todas
# distintas; todas el MISMO síntoma con el gate acoplado. Ahora cada
# eslabón tiene su gate y su evidencia:
#   60.1 el edge responde para jenkins.<dominio>     (tunnel/traefik)
#   60.2 hook registrado + push probe                (GitHub)
#   60.3 la delivery del push quedó 2xx              (HMAC/plugin)
#   60.4 el build EXISTE                             (scan/credencial)
#   60.5 el build queda VERDE                        (pipeline/quota)
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
secrets_workdir   # lib/jenkins.sh materializa el netrc en tmpfs

# ── 60.1 el edge responde para el host de Jenkins ──────────────────
# /login es público (200) — descarta tunnel caído (la red móvil del
# operador — E-1), traefik sin la IngressRoute, DNS público.
#
# #87 (2026-08-13): desde que Access está delante de jenkins.<dom>
# (#76), un curl desnudo recibe 302 al login de Cloudflare. Este gate
# exigía `^(200|403)$`, así que fallaba en ROJO y paraba la fase — el
# fallo espejado del de la 35, y el barato de los dos: rompe fuerte y
# a la vista. edge_origen_responde atraviesa Access con el service
# token de la fase 25 y, si NO puede, lo dice como lo que es (el
# origen no se midió) en vez de como «Jenkins no responde».
gate_diag "edge-jenkins-responde" \
  'kubectl -n infra-edge get pods 2>/dev/null | tail -n 3;
   kubectl -n jenkins-system get pods 2>/dev/null | tail -n 3' \
  retry_net 6 edge_origen_responde "https://jenkins.$ROOT_DOMAIN/login" '^(200|403)$'

# ── 60.2 hook registrado + push probe ──────────────────────────────
WEBHOOK_URL="https://jenkins.$ROOT_DOMAIN/github-webhook/"
# retry_net: con errexit VIVO (F-A #15) un parpadeo de gh mataría la fase:
HOOK_ID="$(retry_net 3 gh api "repos/$GH_OWNER/$APP_REPO/hooks" \
    --jq ".[] | select(.config.url==\"$WEBHOOK_URL\") | .id" | head -n1)"
gate "hook-jenkins-registrado" test -n "$HOOK_ID"
# P1.16 auditoría 2026-07-18: el branch indexing del multibranch es
# ASÍNCRONO — en fresh, el job main puede no existir todavía y el
# jenkins_next_build de abajo moría sin gate propio. Esperarlo con
# evidencia (el log del scan trae la causa si no aparece):
_job_main_existe() { jenkins_get "/job/hello-aegis-mb/job/main/api/json" >/dev/null 2>&1; }
gate_diag "job-main-indexado" \
  'kubectl -n jenkins-system logs sts/jenkins -c jenkins --since=10m 2>/dev/null | grep -iE "branch indexing|scan|hello-aegis" | tail -n 10' \
  poll 300 10 _job_main_existe
# el número del build se captura ANTES del push (carrera lastBuild
# #9, clase bug C); retry_net en el push (red móvil):
NEXT_MB="$(jenkins_next_build hello-aegis-mb/job/main)"
log_info "e2e: push al repo de la app → delivery del hook → build #$NEXT_MB"
run_cmd retry_net 3 bash -c "cd \$(mktemp -d) && \
  git clone --depth 1 https://github.com/$GH_OWNER/$APP_REPO.git app && \
  cd app && git commit --allow-empty -m 'ci: webhook e2e probe' && \
  git push"

# ── 60.3 la delivery del push quedó 2xx DEL LADO GITHUB ────────────
# ESTE es el gate que aísla HMAC/plugin (el equivalente del
# webhook-redeliver-2xx que la 35 ya tenía para argocd y esta fase
# nunca tuvo). 400 acá con edge verde = receptor rechazando la
# firma: HMAC desincronizado (¿store regenerado con Jenkins ya
# arriba? el plugin carga el HMAC AL BOOT — restart del sts) o
# binding JCasC. La evidencia: últimas deliveries con status + log
# del receptor:
# P1.5 auditoría 2026-07-18: GitHub NO re-entrega solo — si el push
# cayó en un 530 del tunnel (la red móvil se fue justo ahí), el poll
# viejo releía la MISMA delivery muerta 300s. Ahora, con el edge ya
# verde (60.1), una delivery fallida se RE-ENTREGA (redeliver) cada
# ~60s dentro de la espera; una delivery en vuelo (status null) solo
# se espera:
_delivery_wait_2xx() {
    local timeout=300 t0=$SECONDS did code line redelivered=0
    while :; do
        line="$(gh api "repos/$GH_OWNER/$APP_REPO/hooks/$HOOK_ID/deliveries" \
            --jq '[.[] | select(.event=="push")][0] | "\(.id) \(.status_code)"' \
            2>/dev/null || true)"
        did="${line%% *}"; code="${line##* }"
        [[ "$code" == 2* ]] && return 0
        (( SECONDS - t0 >= timeout )) && return 1
        if [[ -n "$did" && "$did" != "null" && "$code" =~ ^[0-9]+$ ]] \
           && (( (SECONDS - t0) / 60 >= redelivered )); then
            redelivered=$(( redelivered + 1 ))
            log_warn "delivery push status=$code — redeliver #$redelivered (un 530/timeout del edge NO se re-entrega solo)"
            if ! gh api -X POST \
                 "repos/$GH_OWNER/$APP_REPO/hooks/$HOOK_ID/deliveries/$did/attempts" \
                 >/dev/null 2>&1; then
                log_warn "el redeliver falló (gh/red) — se reintenta en la próxima vuelta"
            fi
        fi
        sleep 10
    done
}
gate_diag "delivery-push-2xx" \
  'gh api "repos/$GH_OWNER/$APP_REPO/hooks/$HOOK_ID/deliveries" \
     --jq ".[0:5][] | \"\(.delivered_at) event=\(.event) status_code=\(.status_code) \(.status)\"" 2>/dev/null;
   log_warn "si status_code=400 con edge verde: HMAC desincronizado — el plugin carga el HMAC AL BOOT (lección #12): si el store regeneró hmac_jenkins con Jenkins ya arriba, kubectl -n jenkins-system rollout restart sts/jenkins y re-correr con --from 60";
   kubectl -n jenkins-system logs sts/jenkins -c jenkins --since=10m 2>/dev/null | grep -iE "webhook|github" | tail -n 8' \
  _delivery_wait_2xx

# ── 60.4 el webhook CREÓ el build (scan multibranch) ───────────────
# delivery 2xx pero sin build = el eslabón del SCAN (credencial
# github-token del scan, quiet period, el job): evidencia separada
# de la del HMAC:
_build_disparado() {
    jenkins_get "/job/hello-aegis-mb/job/main/$NEXT_MB/api/json" \
        >/dev/null 2>&1
}
gate_diag "build-disparado-por-webhook" \
  'jenkins_get "/job/hello-aegis-mb/job/main/api/json" 2>/dev/null | jq "{nextBuildNumber, inQueue: (.inQueueItem != null)}";
   kubectl -n jenkins-system logs sts/jenkins -c jenkins --since=10m 2>/dev/null | grep -iE "scan|branch indexing|hello-aegis" | tail -n 8' \
  poll 300 10 _build_disparado

# ── 60.5 el build queda VERDE (el wait de la lib ya diagnostica la
#     quota en cada vuelta — corrida #11) ───────────────────────────
gate "build-webhook-verde" jenkins_wait_build hello-aegis-mb/job/main 1800 "$NEXT_MB"

log_ok "Webhook end-to-end verificado por ESLABONES: edge → delivery \
2xx → scan → build verde"
