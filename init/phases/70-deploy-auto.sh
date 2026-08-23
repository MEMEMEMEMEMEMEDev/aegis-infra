#!/usr/bin/env bash
# FASE 70 — deploy automático: tenant + Image Updater. El orden es
# método (2026-07-03): tagging determinista YA está en el
# Jenkinsfile v2; ANTI-LOOP PROBADO ANTES del write-back. La
# "secuencia dry-run" murió en la #13 (H5: el CRD v1.2.2 NO tiene
# dryRun — schema imaginario): el freno es el ORDEN (7.3) + el
# dry-run=server del CR contra el CRD vivo (E10). Write-back method
# git/repocreds (el único sin TOFU — A38); la write key ya está
# cifrada desde fase 15.
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
# CR-6 reporte in-VM #14: esta fase MUTA el repo de plataforma — el
# clone local puede estar detras del remoto (fix manual del operador
# en GitHub durante un retome). Sincronizar ANTES de tocar nada:
platform_repo_sync
secrets_workdir   # lib/jenkins.sh materializa el netrc en tmpfs

# argo_sync viene de lib/common.sh (bug C corrida #8: las defs
# locales esperaban solo health — carrera con operationState en
# re-runs; la canónica espera la fase TERMINAL de la operación).

# ── 70.1 tenant org-canary (patrón A completo) ───────────────────
argo_sync org-canary
gate "sa-default-con-pullsecret" bash -c \
  "kubectl -n org-canary get sa default \
     -o jsonpath='{.imagePullSecrets[0].name}' | grep -q regcred-internal"
gate "regcred-vivo" bash -c \
  "kubectl -n org-canary get secret regcred-internal >/dev/null"

# ── 70.2 primer deploy del canary (pull REAL del registry) ─────────
# H1 corrida #13: el newTag del seed asumía que el build #1 pushea
# main-000001, pero el #1 del multibranch es el COSMÉTICO (ABORTED
# sin push) — el primer tag REAL fue main-000002 y el canary pedía
# una imagen inexistente (ImagePullBackOff "not found"). La fuente
# de verdad es EL REGISTRY: se lee el mayor tag main-* publicado y
# se alinea el overlay (commit solo-k8s → el anti-loop lo salta):
REG_HOST="$REGISTRY_HOST_INTERNAL"   # fuente única (P3 auditoría)
registry_creds "$REG_HOST" "$REGISTRY_CLUSTER_IP"
# P1.15 auditoría 2026-07-18: "curl falló" ≠ "lista vacía". El || true
# de antes convertía un parpadeo de red en gate muerto con diagnóstico
# equivocado. La LECTURA se exige (retry + die con la causa real); el
# filtrado vacío sí es un veredicto legítimo del gate:
TAGS_JSON="$(retry_net 3 curl -fsS --max-time 30 \
    --netrc-file "$SECRETS_TMP/registry.netrc" \
    --cacert "$SECRETS_TMP/aegis-ca.crt" \
    "https://$REGISTRY_CLUSTER_IP:5000/v2/hello-aegis/tags/list")" || \
    die "no pude LEER el catálogo del registry (red/registry caído) — esto NO es 'sin tags'; revisar registry-system y re-correr"
FIRST_TAG="$(jq -r '.tags[]?' <<< "$TAGS_JSON" \
  | grep -E '^main-[0-9]{6}$' | sort | tail -n1 || true)"
gate "tag-real-en-registry" test -n "$FIRST_TAG"
run_cmd retry_net 3 bash -c "cd \$(mktemp -d) && \
  git clone --depth 1 https://github.com/$GH_OWNER/$APP_REPO.git app && \
  cd app && \
  sed -i 's/newTag: main-[0-9]\{6\}/newTag: $FIRST_TAG/' \
      k8s/overlays/dev/kustomization.yaml && \
  if git diff --quiet; then echo 'newTag ya alineado con el registry'; \
  else git commit -am 'chore(k8s): newTag = primer tag REAL del registry' && \
       git push; fi"
argo_sync hello-aegis 600
# P1.14 auditoría: el repo-server puede sincronizar la revisión VIEJA
# post-push — Synced solo cuenta al HEAD real del repo de la app
# (patrón F-B extendido; el sha se lee del remoto porque el clone del
# push de arriba fue efímero):
APP_HEAD="$(retry_net 3 git ls-remote \
    "https://github.com/$GH_OWNER/$APP_REPO.git" refs/heads/main)" || \
    die "no pude leer el HEAD remoto de $APP_REPO (red)"
argo_secrets_gate hello-aegis 300 "${APP_HEAD%%$'\t'*}"
# H6 corrida #15 (defensa en profundidad): "newTag ya alineado"
# validaba el kustomization — la INTENCIÓN — pero un
# .argocd-source-*.yaml residual pisa los parámetros y la imagen
# EFECTIVA era otra (main-000009 inexistente → ImagePullBackOff).
# Se valida lo que ArgoCD RESOLVIÓ de verdad: el tag del Deployment
# renderizado debe existir en el catálogo del registry. Existencia
# del deploy primero (patrón H4: existencia→estado):
gate "deploy-canary-existe" poll 180 5 bash -c \
  "kubectl -n org-canary get deploy hello-aegis >/dev/null 2>&1"
EFF_IMG="$(kubectl -n org-canary get deploy hello-aegis \
    -o jsonpath='{.spec.template.spec.containers[0].image}')"
EFF_BASE="${EFF_IMG%%@*}"          # sin @digest (re-run post-Enforce)
EFF_TAG="${EFF_BASE##*:}"
printf '%s' "$TAGS_JSON" > "$SECRETS_TMP/tags.json"
gate_diag "tag-efectivo-en-registry" \
  'log_warn "el tag EFECTIVO del Deployment NO está en el registry — ¿override residual (.argocd-source-*) pisando el newTag? (H6 #15; la siembra de la 12 debió purgarlo)";
   kubectl -n org-canary get deploy hello-aegis -o jsonpath="{.spec.template.spec.containers[0].image}"; echo;
   jq -r ".tags[]?" "$SECRETS_TMP/tags.json"' \
  bash -c "jq -e --arg t '$EFF_TAG' '.tags[]? | select(. == \$t)' \
     '$SECRETS_TMP/tags.json' >/dev/null"
# ESTE es el gate definitorio del camino registry→kubelet (TLS+auth
# +mirror+/etc/hosts): un pod REAL pulleó una imagen REAL. H7 #13:
# al fallar, la causa vive en events/describe — mostrarla:
gate_diag "canary-corriendo" \
  'kubectl -n org-canary get events --sort-by=.lastTimestamp | tail -n 15;
   kubectl -n org-canary describe pod -l app=hello-aegis 2>/dev/null | tail -n 25' \
  bash -c "kubectl -n org-canary rollout status deploy/hello-aegis --timeout=300s >/dev/null"

# ── 70.3 anti-loop verificado ANTES del write-back (regla 7.3) ─────
# El Jenkinsfile v2 trae detect-change estructural (solo k8s/** →
# SKIP). Gate: commit que SOLO toca k8s/** NO debe producir build
# con stages de build/push:
log_info "gate anti-loop: commit solo-k8s => el pipeline debe saltar build"
# número del build ANTES del push (carrera lastBuild #9: el wfapi de
# lastBuild podía describir el build ANTERIOR, no el del probe):
NEXT_PROBE="$(jenkins_next_build hello-aegis-mb/job/main)"
# el sed sale 0 AUNQUE no matchee nada (bug latente cazado en la
# revisión post-#4): en la PRIMERA corrida el seed no tiene la línea
# antiloop-probe → sed "exitoso" sin cambio → commit -am moría con
# "nothing to commit". grep decide de verdad si existe la línea:
run_cmd retry_net 3 bash -c "cd \$(mktemp -d) && \
  git clone --depth 1 https://github.com/$GH_OWNER/$APP_REPO.git app && \
  cd app && \
  if grep -q '^# antiloop-probe' k8s/overlays/dev/kustomization.yaml; then \
      sed -i 's/^# antiloop-probe.*/# antiloop-probe $(date -u +%s)/' \
          k8s/overlays/dev/kustomization.yaml; \
  else \
      echo '# antiloop-probe $(date -u +%s)' >> k8s/overlays/dev/kustomization.yaml; \
  fi && \
  git commit -am 'chore(k8s): antiloop probe' && git push"
# gate estructural: el build DEL PROBE debe terminar verde CON los
# stages saltados. H3 corrida #13: /wfapi/ lo provee el plugin
# pipeline-stage-view, que NO está instalado (pipeline-stage-STEP y
# pipeline-stage-tags-metadata son OTROS plugins) → 404 eterno con
# el anti-loop FUNCIONANDO PERFECTO. Se valida contra el core
# (/api/json, siempre presente) + el console del build (el marcador
# "skipped due to when conditional" — verificado en vivo #13 en los
# builds #4/#5 del probe):
_antiloop_skipped() {
    jenkins_get "/job/hello-aegis-mb/job/main/$NEXT_PROBE/api/json" \
        2>/dev/null | jq -e '.result == "SUCCESS"' >/dev/null || return 1
    jenkins_get "/job/hello-aegis-mb/job/main/$NEXT_PROBE/consoleText" \
        2>/dev/null | grep -q 'skipped due to when conditional'
}
gate_diag "anti-loop-build-salteado" \
  'jenkins_get "/job/hello-aegis-mb/job/main/$NEXT_PROBE/api/json" 2>/dev/null | jq "{result, building}";
   jenkins_get "/job/hello-aegis-mb/job/main/$NEXT_PROBE/consoleText" 2>/dev/null | tail -n 20' \
  poll 600 20 _antiloop_skipped

# ── 70.4 el pipeline escribe el DIGEST en git ──────────────────────
#
# ACÁ VIVÍA el alta del argocd-image-updater: instalar el chart, esperar
# su CRD en el discovery, validar el CR con dry-run=server, agregarlo al
# kustomization en el mismo commit, y probar el ciclo completo esperando
# su write-back. Se retiró en #59 junto con el componente.
#
# El modelo de hoy es más corto y tiene menos partes móviles: el pipeline
# que CONSTRUYÓ la imagen ya sabe su digest y lo escribe en el overlay
# (etapa `desplegar`). El updater tenía que redescubrirlo sondeando el
# registry, con un poller que se cuelga y un write-back que puede no
# aterrizar — que es exactamente lo que pasó durante meses sin que nadie
# lo viera (#55).
#
# LO QUE NO SE PIERDE es el gate: aquél probaba que el ciclo cerraba de
# verdad, y éste prueba lo mismo contra el mecanismo nuevo. El overlay
# del canario nace con un digest MARCADOR de sesenta y cuatro ceros,
# obviamente falso a propósito; que ahí haya un digest real es la prueba
# de que el pipeline lo escribió y de que el commit aterrizó en el repo.
#
# Un digest real Y DISTINTO del marcador: chequear sólo el formato
# dejaría pasar los ceros, que tienen forma perfecta de digest.
gate_diag "pipeline-escribio-el-digest" \
  'gh api "repos/'"$GH_OWNER"'/'"$APP_REPO"'/contents/k8s/overlays/dev/kustomization.yaml" \
     --jq .content | base64 -d | grep -i digest' \
  poll 900 30 bash -c \
  "gh api 'repos/$GH_OWNER/$APP_REPO/contents/k8s/overlays/dev/kustomization.yaml' \
     --jq '.content' 2>/dev/null | base64 -d \
   | grep -qE 'digest: sha256:[0-9a-f]{64}' \
   && ! gh api 'repos/$GH_OWNER/$APP_REPO/contents/k8s/overlays/dev/kustomization.yaml' \
        --jq '.content' 2>/dev/null | base64 -d \
      | grep -q 'digest: sha256:0\{64\}'"

log_ok "Tenant vivo, canary desplegado con pull real, anti-loop \
verificado, y el digest escrito por el propio pipeline"
