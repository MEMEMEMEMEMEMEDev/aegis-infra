#!/usr/bin/env bash
# PHASE 30 — ArgoCD: the ONLY imperative installation in the stack
# (D6). helm install with THE SAME values the self Application will
# use (adoption contract: exact releaseName + identical values — a
# pattern validated in Batch 1b, 2026-06-17:62-103). The bootstrap
# Secrets are created with KUBECTL, byte-preserving — NEVER tofu (D2:
# the age key never touches a tfstate).
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/aegis.key}"

gate "kube-context" check_kube_context "$KUBE_CONTEXT_EXPECTED"
VALUES="$PLATFORM_DIR/k8s/base/platform/argocd/values.yaml"
gate "values-presentes" test -f "$VALUES"

# ── ns + bootstrap Secrets (kubectl, not tofu) ─────────────────────
run_cmd kubectl create namespace argocd --dry-run=client -o yaml \
    | run_cmd kubectl apply -f -

# P2.6 audit 2026-07-18: skip-if-exists left ROTATED material stale in
# the cluster (the source on disk/in the store changed, the live
# Secret did not). A kubectl apply of the dry-run is idempotent AND
# convergent: same material = no-op, rotated material = update.

# 1) argocd-sops-age: the age key for KSOPS. --from-file (A6).
#    The value is NEVER shown. apply ALWAYS (convergent):
run_cmd bash -c \
  "kubectl -n argocd create secret generic argocd-sops-age \
     --from-file=keys.txt='$SOPS_AGE_KEY_FILE' \
     --dry-run=client -o yaml | kubectl apply -f -"
log_ok "Secret argocd-sops-age converged (kubectl, outside every state)"

# 2) ops-stack-repo (the platform RO deploy key): the .enc.yaml was
#    encrypted in phase 15; ArgoCD does not exist yet to KSOPS it, so
#    THIS one is applied by decrypting into a pipe (never to disk).
#    apply ALWAYS (same reason):
run_cmd bash -c \
  "sops -d '$PLATFORM_DIR/k8s/base/platform/argocd-secrets/secret-ops-stack-repo.enc.yaml' \
   | kubectl apply -f -"
log_ok "Secret ops-stack-repo converged (sops→kubectl pipe, no disk)"

# 3) argocd-redis: with redisSecretInit=false (values — the Job hook
#    would run on every sync of the self App) the chart does NOT
#    create this Secret, and the redis container references it
#    WITHOUT optional → CreateContainerConfigError. VERIFIED against
#    the real render of chart 9.5.20 (final v2 close-out). v1 never
#    saw it because its original install ran the Job. Bootstrap Secret
#    #3, same D2 pattern (random in tmpfs, kubectl, never shown):
# P2.6: the redis password comes from the STORE (gen_or_restore) — an
# always-convergent apply demands a stable origin across runs (a fresh
# random per run would ROTATE the auth against an already-live redis):
secrets_workdir
REDIS_PASS="$(gen_or_restore redis_auth gen_password_b64)"
run_cmd bash -c \
  "kubectl -n argocd create secret generic argocd-redis \
     --from-file=auth='$REDIS_PASS' \
     --dry-run=client -o yaml | kubectl apply -f -"
log_ok "Secret argocd-redis converged (the chart does not create it with the Job off)"

# ── helm install: the WHOLE adoption contract DERIVED from the App ─
# Single source = k8s/argocd-apps/core.yaml (the manifest ArgoCD will
# apply forever). The one-shot installer reads chart, version, repo,
# releaseName and values from there — an install-vs-App divergence is
# impossible BY CONSTRUCTION (there is no second place to edit).
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
assert values.startswith(prefix), f"valueFiles without a $values ref: {values}"
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
# the App's values IS the install's values (the same real file):
gate "contrato-values-coinciden" test "$APP_VALUES" -ef "$VALUES"
log_info "contract from core.yaml: $ARGO_CHART@$ARGO_VER release=$ARGO_RELEASE"

run_cmd retry_net 3 helm repo add argo "$ARGO_REPO"
run_cmd retry_net 3 helm repo update argo
# P1.12 audit 2026-07-18: a release in pending-* (a previous run that
# died mid-install — the broken pipe of #15 being the typical case)
# JAMS the re-run: helm refuses both install AND upgrade over pending.
# Detection + an explicit way out of the zombie state (an uninstall in
# a greenfield bootstrap is safe: what follows recreates it whole):
REL_STATUS="$(helm -n argocd status "$ARGO_RELEASE" -o json 2>/dev/null \
              | jq -r '.info.status // empty' || true)"
if [[ "$REL_STATUS" == pending-* || "$REL_STATUS" == failed ]]; then
    log_warn "release $ARGO_RELEASE in state '$REL_STATUS' (a previous run died halfway) — uninstalling and reinstalling clean"
    run_cmd helm -n argocd uninstall "$ARGO_RELEASE" --wait || \
        die "could not uninstall the zombie release '$ARGO_RELEASE' — check 'helm -n argocd status $ARGO_RELEASE' by hand"
fi
if ! helm -n argocd status "$ARGO_RELEASE" >/dev/null 2>&1; then
    run_cmd helm install "$ARGO_RELEASE" "argo/$ARGO_CHART" -n argocd \
        --version "$ARGO_VER" -f "$VALUES" --wait --timeout 10m
else
    log_info "release $ARGO_RELEASE already exists — idempotent helm upgrade"
    run_cmd helm upgrade "$ARGO_RELEASE" "argo/$ARGO_CHART" -n argocd \
        --version "$ARGO_VER" -f "$VALUES" --wait --timeout 10m
fi

# ── gates: KSOPS TRULY operational (not 'the pod is running') ─────
gate "repo-server-ready" bash -c \
  "kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s >/dev/null"
gate "ksops-binario" bash -c \
  "kubectl -n argocd exec deploy/argocd-repo-server -c repo-server -- \
     sh -c 'command -v ksops' >/dev/null"
gate "age-montada" bash -c \
  "kubectl -n argocd exec deploy/argocd-repo-server -c repo-server -- \
     sh -c 'test -s /.config/sops/age/keys.txt'"
# note: the FUNCTIONAL gate for KSOPS (a real decryption) is the sync
# of argocd-secrets in phase 35 — that is the client→server test.

log_ok "ArgoCD alive with KSOPS; bootstrap Secrets outside tofu"
