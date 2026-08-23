#!/usr/bin/env bash
# FASE 30 — ArgoCD: la ÚNICA instalación imperativa del stack (D6).
# helm install con LOS MISMOS values que la Application self usará
# (contrato de adopción: releaseName exacto + values idénticos —
# patrón validado en Tanda 1b, 2026-06-17:62-103). Los Secrets de
# bootstrap se crean por KUBECTL, byte-preserving — NUNCA tofu (D2:
# la age key jamás toca un tfstate).
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/aegis.key}"

gate "kube-context" check_kube_context "$KUBE_CONTEXT_EXPECTED"
VALUES="$PLATFORM_DIR/k8s/base/platform/argocd/values.yaml"
gate "values-presentes" test -f "$VALUES"

# ── ns + Secrets de bootstrap (kubectl, no tofu) ───────────────────
run_cmd kubectl create namespace argocd --dry-run=client -o yaml \
    | run_cmd kubectl apply -f -

# P2.6 auditoría 2026-07-18: el skip-if-exists dejaba material
# ROTADO stale en el cluster (la fuente en disco/store cambió, el
# Secret vivo no). kubectl apply del dry-run es idempotente Y
# convergente: mismo material = no-op, material rotado = actualiza.

# 1) argocd-sops-age: la age key para KSOPS. --from-file (A6).
#    El valor NUNCA se muestra. apply SIEMPRE (convergente):
run_cmd bash -c \
  "kubectl -n argocd create secret generic argocd-sops-age \
     --from-file=keys.txt='$SOPS_AGE_KEY_FILE' \
     --dry-run=client -o yaml | kubectl apply -f -"
log_ok "Secret argocd-sops-age convergido (kubectl, fuera de todo state)"

# 2) ops-stack-repo (deploy key RO de plataforma): el .enc.yaml se
#    cifró en fase 15; ArgoCD aún no existe para KSOPS-earlo, así
#    que ESTE se aplica descifrando a un pipe (nunca a disco).
#    apply SIEMPRE (misma razón):
run_cmd bash -c \
  "sops -d '$PLATFORM_DIR/k8s/base/platform/argocd-secrets/secret-ops-stack-repo.enc.yaml' \
   | kubectl apply -f -"
log_ok "Secret ops-stack-repo convergido (pipe sops→kubectl, sin disco)"

# 3) argocd-redis: con redisSecretInit=false (values — el Job hook
#    correría en cada sync de la App self) el chart NO crea este
#    Secret, y el container redis lo referencia SIN optional →
#    CreateContainerConfigError. VERIFICADO contra el render real
#    del chart 9.5.20 (cierre final v2). v1 no lo vio porque su
#    install original corrió el Job. Bootstrap Secret #3, mismo
#    patrón D2 (random en tmpfs, kubectl, jamás mostrado):
# P2.6: el password de redis sale del STORE (gen_or_restore) — el
# apply siempre-convergente exige un origen estable entre corridas
# (un random nuevo por corrida ROTARÍA el auth con redis ya vivo):
secrets_workdir
REDIS_PASS="$(gen_or_restore redis_auth gen_password_b64)"
run_cmd bash -c \
  "kubectl -n argocd create secret generic argocd-redis \
     --from-file=auth='$REDIS_PASS' \
     --dry-run=client -o yaml | kubectl apply -f -"
log_ok "Secret argocd-redis convergido (el chart no lo crea con el Job off)"

# ── helm install: TODO el contrato de adopción DERIVADO de la App ──
# Fuente única = k8s/argocd-apps/core.yaml (el manifest que ArgoCD
# aplicará para siempre). El instalador one-shot lee de ahí chart,
# versión, repo, releaseName y values — divergencia install-vs-App
# imposible POR CONSTRUCCIÓN (no hay segundo lugar que editar).
CORE="$PLATFORM_DIR/k8s/argocd-apps/core.yaml"
readarray -t CONTRACT < <(python3 - "$CORE" <<'EOF'
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
app = next(d for d in docs
           if d.get("kind") == "Application"
           and d["metadata"]["name"] == "argocd")
helm_src = next(s for s in app["spec"]["sources"] if "chart" in s)
values = helm_src["helm"]["valueFiles"][0]
prefix = "$values/"
assert values.startswith(prefix), f"valueFiles sin ref $values: {values}"
print(helm_src["repoURL"])
print(helm_src["chart"])
print(helm_src["targetRevision"])
print(helm_src["helm"]["releaseName"])
print(values[len(prefix):])
EOF
)
ARGO_REPO="${CONTRACT[0]}" ARGO_CHART="${CONTRACT[1]}"
ARGO_VER="${CONTRACT[2]}"  ARGO_RELEASE="${CONTRACT[3]}"
APP_VALUES="$PLATFORM_DIR/${CONTRACT[4]}"
# el values de la App ES el values del install (mismo archivo real):
gate "contrato-values-coinciden" test "$APP_VALUES" -ef "$VALUES"
log_info "contrato desde core.yaml: $ARGO_CHART@$ARGO_VER release=$ARGO_RELEASE"

run_cmd retry_net 3 helm repo add argo "$ARGO_REPO"
run_cmd retry_net 3 helm repo update argo
# P1.12 auditoría 2026-07-18: un release en pending-* (corrida
# anterior muerta a mitad del install — broken pipe de la #15 es el
# caso típico) TRABA el re-run: helm rechaza install Y upgrade sobre
# pending. Detección + salida explícita del estado zombie (uninstall
# en bootstrap greenfield es seguro: lo que sigue lo recrea entero):
REL_STATUS="$(helm -n argocd status "$ARGO_RELEASE" -o json 2>/dev/null \
              | jq -r '.info.status // empty' || true)"
if [[ "$REL_STATUS" == pending-* || "$REL_STATUS" == failed ]]; then
    log_warn "release $ARGO_RELEASE en estado '$REL_STATUS' (corrida anterior muerta a mitad) — uninstall y reinstalación limpia"
    run_cmd helm -n argocd uninstall "$ARGO_RELEASE" --wait || \
        die "no pude desinstalar el release zombie '$ARGO_RELEASE' — revisar 'helm -n argocd status $ARGO_RELEASE' a mano"
fi
if ! helm -n argocd status "$ARGO_RELEASE" >/dev/null 2>&1; then
    run_cmd helm install "$ARGO_RELEASE" "argo/$ARGO_CHART" -n argocd \
        --version "$ARGO_VER" -f "$VALUES" --wait --timeout 10m
else
    log_info "release $ARGO_RELEASE ya existe — helm upgrade idempotente"
    run_cmd helm upgrade "$ARGO_RELEASE" "argo/$ARGO_CHART" -n argocd \
        --version "$ARGO_VER" -f "$VALUES" --wait --timeout 10m
fi

# ── gates: KSOPS operativo DE VERDAD (no 'pod corriendo') ─────────
gate "repo-server-ready" bash -c \
  "kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s >/dev/null"
gate "ksops-binario" bash -c \
  "kubectl -n argocd exec deploy/argocd-repo-server -c repo-server -- \
     sh -c 'command -v ksops' >/dev/null"
gate "age-montada" bash -c \
  "kubectl -n argocd exec deploy/argocd-repo-server -c repo-server -- \
     sh -c 'test -s /.config/sops/age/keys.txt'"
# nota: el gate FUNCIONAL de KSOPS (descifrado real) es el sync de
# argocd-secrets en la fase 35 — ese es el test cliente→servidor.

log_ok "ArgoCD vivo con KSOPS; Secrets de bootstrap fuera de tofu"
