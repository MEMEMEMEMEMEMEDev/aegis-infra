#!/usr/bin/env bash
# FASE 35 — handover a GitOps: root App + syncs en ORDEN (el orden ES
# el contrato — ADR-0015:64-74 y D5). En v2 TODO el plano de
# plataforma entra por acá (D6): cert-manager, PKI, traefik,
# cloudflared… nada fue pre-instalado por tofu, así que no hay
# adopción — es despliegue limpio en secuencia.
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"

# argo_sync viene de lib/common.sh (bug C corrida #8: la def local
# esperaba solo health — carrera con operationState en re-runs; la
# canónica espera la fase TERMINAL de la operación nueva).

# ── AppProjects ANTES que root (W-06 / clase C1) ───────────────────
# root y las Apps referencian aegis-bootstrap/platform/tenant; los
# proyectos deben existir antes o el App queda "project not found".
# Infra de bootstrap imperativa (como los Secrets D2), fuera del path
# del App-of-Apps para que root no los gestione:
#
# DOS archivos, y los dos hacen falta:
#   appprojects.yaml           el sustrato (bootstrap, platform) y lo que
#                              no sale de un contrato (canary, heredados)
#   appprojects-tenants.yaml   DERIVADO por `bin/aegis-org` de los
#                              contratos que declaran repo
# Sin el segundo, las Applications de las organizaciones arrancan y
# ArgoCD las deja en "project not found" (#19).
run_cmd kubectl apply -f "$PLATFORM_DIR/k8s/bootstrap/appprojects.yaml"
# El derivado puede estar VACÍO y eso es correcto: una instancia recién
# arrancada no tiene contratos todavía. `kubectl apply` sobre un archivo
# sin objetos sale 1 ("no objects passed to apply") y mataría la fase.
# La pregunta se hace estructuralmente (yaml_has_docs), no con un grep
# del kind: el encabezado del archivo lo nombra en prosa.
if yaml_has_docs "$PLATFORM_DIR/k8s/bootstrap/appprojects-tenants.yaml"; then
    run_cmd kubectl apply -f "$PLATFORM_DIR/k8s/bootstrap/appprojects-tenants.yaml"
else
    log_info "appprojects-tenants.yaml sin documentos: 0 contratos en orgs/, nada que derivar"
fi
gate "appprojects-creados" bash -c \
  "kubectl get appproject -n argocd aegis-bootstrap aegis-platform aegis-tenant-canary >/dev/null 2>&1"
# El gate de arriba mira los tres FIJOS. Los derivados se comprueban
# contra el archivo y no contra una lista escrita acá: enumerarlos sería
# un cuarto lugar donde acordarse de agregar la organización nueva, que
# es exactamente lo que #19 vino a sacar.
gate "appprojects-derivados" bash -c '
  falta=""
  for p in $(grep -oP "(?<=^  name: )aegis-tenant-\S+" \
             "'"$PLATFORM_DIR"'/k8s/bootstrap/appprojects-tenants.yaml" 2>/dev/null); do
      kubectl get appproject -n argocd "$p" >/dev/null 2>&1 || falta="$falta $p"
  done
  [[ -z "$falta" ]] || { echo "AppProjects derivados que no se crearon:$falta"; exit 1; }'

# ── root (sync MANUAL siempre — ADR-0012) ──────────────────────────
run_cmd kubectl apply -f "$PLATFORM_DIR/k8s/argocd-apps/root.yaml"
argo_sync root 120

# ── ORDEN FORZADO: PROVEEDORES ANTES QUE CONSUMIDORES ──────────────
# Hallazgo A v1.1 (dependencia de webhook INVERTIDA, determinista en
# cluster frío): argocd-secrets sincronizaba PRIMERA y contenía un
# Certificate — cuyo admission webhook lo provee cert-manager, que
# se sincronizaba DESPUÉS → "no endpoints available for service
# cert-manager-webhook" → fase 35 caída. Parecía intermitente solo
# porque el auto-sync de la root App a veces ganaba la carrera.
# El orden nuevo pone a los PROVEEDORES (CRDs + webhooks) primero;
# ninguno de ellos depende de los Secrets de argocd-secrets, así que
# adelantarlos no cuesta nada. La restricción que motivó el orden
# viejo se conserva intacta: argocd-secrets SIGUE yendo antes que
# argocd-self (si no, el puntero $github-webhook:token queda literal
# y el webhook da 400 hasta el restart — ADR-0015).

# 1. cert-manager: CRDs + el webhook que gobierna todo Certificate.
argo_sync cert-manager 600
# el Healthy de la App NO alcanza (A v1.1): la señal es que el
# Service del webhook tenga ENDPOINTS — cert-manager tarda ~1-2 min
# desde cero y en esa ventana TODO Certificate es rechazado:
gate "cert-manager-webhook-sirviendo" \
    webhook_serving cert-manager cert-manager-webhook 300

# 2. PKI interna (ClusterIssuers + el Certificate aegis-ca-trust,
#    que vive ACÁ desde el fix de A: junto al issuer que referencia):
argo_sync aegis-ca-issuer
argo_sync cert-manager-issuers      # LE staging+prod (DNS-01)

# 3. traefik: instala el CRD IngressRoute que usa argocd-secrets.
argo_sync traefik 600               # trustedIPs horneadas (A31)

# 4. argocd-secrets: ya con webhook y CRDs disponibles. Este sync es
#    ADEMÁS el gate funcional de KSOPS (primer descifrado real):
argo_sync argocd-secrets

# argo_secrets_gate (corrida #4): distingue build de kustomize ROTO
# (ComparisonError — acoplamiento temporal) de timing, y exige
# Synced de verdad (Healthy es trivial para Apps de Secrets):
argo_secrets_gate argocd-secrets
# el sync es asíncrono respecto al apply de recursos — poll, no
# check instantáneo (corrida #4, bug 6):
gate "ksops-funcional" poll 180 5 bash -c \
  "kubectl -n argocd get secret github-webhook >/dev/null 2>&1"
gate "generator-completo" poll 180 5 bash -c \
  "kubectl -n argocd get secret hello-aegis-repo ops-stack-repo >/dev/null 2>&1"
# (A7: validación post-sync SIEMPRE — Synced+Healthy no garantiza
#  los Secrets si falta un entry del generator)

# 5. argocd self-adoption (App sin automated — ADR-0012).
#    Corridas #7/#8: quedó Synced/Healthy — el OutOfSync de la #5 era
#    git transitorio, no drift (riesgo #2 CERRADO positivo). El
#    argo_sync canónico ya espera la fase TERMINAL de la operación
#    (bug C #8: la carrera health-vs-operationState en re-runs vivía
#    ACÁ). Se conserva UN reintento por git transitorio (la red del
#    operador — "failed to get git client" visto en #5/#8):
if ! argo_sync argocd 600; then
    log_warn "sync del App self falló (¿git transitorio?) — reintento una vez"
    argo_sync argocd 600 || \
        die "sync del App self falló dos veces — revisar repo-server/red y --from 35"
fi
if ! kubectl -n argocd get application argocd \
       -o jsonpath='{.status.sync.status}' | grep -qx Synced; then
    log_warn "App argocd OutOfSync post-sync exitoso — residuo de adopción (benigno: Healthy + sin automated); recursos:"
    kubectl -n argocd get application argocd -o jsonpath=\
'{range .status.resources[?(@.status=="OutOfSync")]}{.kind}/{.name}{"\n"}{end}' >&2 || true
fi
gate "argocd-self-healthy" bash -c \
  "kubectl -n argocd get application argocd \
     -o jsonpath='{.status.health.status}' | grep -qx Healthy"

# 6. lo que faltaba del plano base (cert-manager, la PKI y traefik
#    ya se sincronizaron ARRIBA, antes de argocd-secrets — fix del
#    Hallazgo A v1.1; re-sincronizarlos acá sería redundante):
argo_sync cloudflare-tunnel         # cloudflared (token de fase 25)

# ── gates de edge end-to-end ───────────────────────────────────────
gate "cloudflared-conectado" bash -c \
  "kubectl -n infra-edge rollout status deploy/cloudflared --timeout=180s >/dev/null"
# DNS público + tunnel + traefik respondiendo (404 de traefik = OK,
# aún no hay IngressRoutes de apps). P1.13 auditoría: retry_net 6
# daba ~30s a la PROPAGACIÓN DNS pública de un CNAME recién creado —
# tarda minutos con normalidad. poll 600 10 con curl acotado.
#
# #87 (2026-08-13): este gate aceptaba `30[12]`, y desde que Access
# está delante de argocd.<dom> (#76) un 302 es EXACTAMENTE lo que
# devuelve el borde de Cloudflare cuando NO te deja pasar. O sea: el
# gate llamado «edge-responde» pasaba sin que la petición entrara al
# túnel, sin tocar traefik y sin ver a argocd-server. Verde con el
# cluster entero apagado.
#
# edge_origen_responde atraviesa Access con el service token que la
# fase 25 dejó en el store, y separa los tres desenlaces que antes
# eran uno solo: el origen contestó / Access interceptó / no hubo
# respuesta. Los códigos siguen siendo 200 o 404 (traefik sin
# IngressRoute todavía) — pero ahora vienen DEL ORIGEN.
#
# El gate se escribe con continuaciones de línea (\) y el diagnóstico
# en UNA línea a propósito: el check 67 de verify-static une las
# continuaciones y exige ver `poll` en la misma línea lógica que
# "edge-responde". Un salto de línea real dentro del string lo rompe.
DIAG35='kubectl -n infra-edge get pods 2>/dev/null | tail -n 3; kubectl -n infra-edge logs deploy/cloudflared --tail=15 2>/dev/null'
gate_diag "edge-responde" "$DIAG35" \
  poll 600 10 edge_origen_responde "https://argocd.$ROOT_DOMAIN" '^(200|404)$'

# webhook GitHub→ArgoCD funcional (el HMAC de los DOS lados es el
# mismo porque la fase 15 lo RE-SINCRONIZA siempre — PATCH sobre hooks
# existentes, bug corrida #10: un hook sobreviviente con HMAC viejo
# daba 400 acá con el edge perfectamente sano). Test real: redeliver de la
# última delivery y esperar 2xx del lado GitHub. El hook se resuelve
# por su URL (argocd-server escucha HTTP plano detrás del edge; la
# URL pública es https):
WEBHOOK_URL="https://argocd.$ROOT_DOMAIN/api/webhook"
# retry_net: con errexit VIVO (F-A #15) un parpadeo de gh acá mataría
# la fase — antes caía mudo a un gate 2 líneas después:
HOOK_ID="$(retry_net 3 gh api "repos/$GH_OWNER/$PLATFORM_REPO/hooks" \
    --jq ".[] | select(.config.url==\"$WEBHOOK_URL\") | .id")"
gate "hook-argocd-registrado" test -n "$HOOK_ID"
DELIVERY_ID="$(retry_net 3 gh api \
    "repos/$GH_OWNER/$PLATFORM_REPO/hooks/$HOOK_ID/deliveries" \
    --jq '.[0].id')"
gate "hook-tiene-deliveries" test -n "$DELIVERY_ID"
run_cmd gh api -X POST \
    "repos/$GH_OWNER/$PLATFORM_REPO/hooks/$HOOK_ID/deliveries/$DELIVERY_ID/attempts"
# el redeliver es asíncrono; la delivery más reciente debe quedar 2xx:
gate "webhook-redeliver-2xx" poll 180 5 bash -c \
    "gh api 'repos/$GH_OWNER/$PLATFORM_REPO/hooks/$HOOK_ID/deliveries' \
       --jq '.[0].status_code' | grep -q '^2'"

log_ok "GitOps operativo: root + plano base Healthy, edge respondiendo"
