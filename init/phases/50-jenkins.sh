#!/usr/bin/env bash
# FASE 50 — CI: Jenkins con JOBS-AS-CODE desde el nacimiento (27
# §1.3: el init copia un patrón probado; los jobs viven en values,
# no en el PVC). Secrets ANTES del chart (regla 5.2, boot loop si
# no). Cierra con la imagen de tooling CI construida y pusheada.
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
# CR-6 reporte in-VM #14: esta fase MUTA el repo de plataforma — el
# clone local puede estar detras del remoto (fix manual del operador
# en GitHub durante un retome). Sincronizar ANTES de tocar nada:
platform_repo_sync
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/aegis.key}"

# argo_sync viene de lib/common.sh (bug C corrida #8: las defs
# locales esperaban solo health — carrera con operationState en
# re-runs; la canónica espera la fase TERMINAL de la operación).

# ── 50.0 jenkins-admin (T2-A random — C10 saldada por protocolo) ───
# gen_or_restore + sin pausa de resguardo (D11): el password queda
# cifrado en el store y en el Secret KSOPS — recuperable con la age
# key. Para uso interactivo posterior: docs/protocols/
# rotation-checklist.md explica cómo leerlo del store.
secrets_workdir
ADMIN_PASS="$(gen_or_restore jenkins_admin_pass gen_password_b64)"
printf 'admin' > "$SECRETS_TMP/jenkins_admin_user"
make_enc_secret jenkins-admin jenkins-system \
    "$PLATFORM_DIR/k8s/base/platform/jenkins-secrets/secret-jenkins-admin.enc.yaml" \
    "username=$SECRETS_TMP/jenkins_admin_user" \
    "password=$ADMIN_PASS"

# clase F auditoría: sin || true que trague un commit fallido real:
git_commit_if_changes "$PLATFORM_DIR" "feat(jenkins): admin secret"
git_push_verified "$PLATFORM_DIR"

# ── 50.1 Secrets → chart (ORDEN: 5.2) ─────────────────────────────
argo_sync jenkins-secrets
# F-B corrida #15: el sync murió por DNS transitorio y el gate pasó
# con el Synced VIEJO — ahora exige la revisión RECIÉN pusheada:
argo_secrets_gate jenkins-secrets 300 \
    "$(git -C "$PLATFORM_DIR" rev-parse HEAD)"
gate "los-6-secrets" poll 180 5 bash -c "kubectl -n jenkins-system get secret \
  jenkins-admin hello-aegis-repo regcred-internal github-token \
  ops-stack-repo-ro github-webhook-hmac >/dev/null 2>&1"
# (D11: github-token + ops-stack-repo-ro reemplazan a la GitHub App.
#  cosign-signing-key llega en fase 80; su entry NO está en el
#  generator todavía — la fase 80 agrega archivo+entry en el mismo
#  commit. Acá el generator lista exactamente los 6 que existen.)

argo_sync jenkins 900
# P1.4 auditoría 2026-07-18: el boot de Jenkins fue el paso MÁS LENTO
# legítimo de la corrida real (~8 min: el init-container descarga los
# plugins por la red del operador) y su gate era un rollout status
# único y MUDO. wait_rollout: espera generosa con evidencia periódica
# (E-1); al fallar, el diagnóstico trae los logs del init-container —
# donde vive la causa (plugin truncado, red, mirror caído). Deuda
# anotada (VALIDACION §4): pre-hornear los plugins en una imagen
# propia mataría la descarga por completo:
gate_diag "jenkins-ready" \
  'kubectl -n jenkins-system get pods;
   kubectl -n jenkins-system logs jenkins-0 -c init --tail=25 2>/dev/null;
   kubectl -n jenkins-system get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 8' \
  wait_rollout jenkins-system sts/jenkins 1800

# ── 50.2 jobs-as-code: el seed corrió? (verificación REAL) ─────────
# Los jobs están en JCasC job-dsl dentro de values.yaml (D9). El
# gate es que el job EXISTE vía API, no "el chart dice". Auth por
# lib/jenkins.sh: netrc por stdin, password fuera de TODO argv (A27).
_job_exists() { jenkins_get "/job/$1/api/json" >/dev/null; }
gate "job-hello-aegis-mb-existe" retry_net 5 _job_exists hello-aegis-mb
# P1.9 auditoría: era single-shot al lado de su gate hermano con
# retry — el seed del job-dsl corre async al boot:
gate "job-ci-images-existe" retry_net 5 _job_exists ci-images

# ── 50.3 imagen de tooling CI (aegis-ci-cosign) ────────────────────
# En v2 el build de la imagen NO es manual (doc 26 §16.9): es un
# job jenkins 'ci-images' (también seed del job-dsl) que buildea
# ci-images/cosign/Containerfile y pushea al registry. Trigger por
# API (crumb CSRF en lib/jenkins.sh) + espera del resultado:
log_info "disparando build ci-images (buildah→push: pull/push REAL del registry)"
# F-C/F-D corrida #15: dos FAILURE seguidos MUDOS (la causa vivía en
# el console, nunca impreso) y cada reintento costaba re-correr la
# fase a mano. jenkins_build_retry: captura next ANTES del POST
# (carrera #9), imprime la cola del console al fallar, y re-dispara
# SOLO si el fallo tiene firma de RED transitoria (la red móvil):
gate "ci-images-build-verde" jenkins_build_retry ci-images 1800 3

# ── 50.4 gate definitorio: la imagen ESTÁ en el catálogo ───────────
# lectura real del registry (registry_creds: netrc+CA en tmpfs, sin
# mostrar valores). --resolve porque el host no resuelve .svc (A30).
REG_HOST="$REGISTRY_HOST_INTERNAL"   # fuente única (P3 auditoría)
registry_creds "$REG_HOST" "$REGISTRY_CLUSTER_IP"
gate "aegis-ci-cosign-en-catalogo" retry_net 3 bash -c \
  "curl -fsS --netrc-file '$SECRETS_TMP/registry.netrc' \
     --cacert '$SECRETS_TMP/aegis-ca.crt' \
     --resolve '${REG_HOST%%:*}:5000:$REGISTRY_CLUSTER_IP' \
     'https://$REG_HOST/v2/aegis-ci-cosign/tags/list' \
   | jq -e '.tags | length > 0' >/dev/null"

log_ok "Jenkins vivo con jobs-as-code (PVC descartable), admin \
random en el store cifrado, tooling CI construido y verificado en el registry"
