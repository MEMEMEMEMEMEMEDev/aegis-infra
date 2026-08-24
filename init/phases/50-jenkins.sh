#!/usr/bin/env bash
# PHASE 50 — CI: Jenkins with JOBS-AS-CODE from birth (27 §1.3: the
# init copies a proven pattern; the jobs live in values, not in the
# PVC). Secrets BEFORE the chart (rule 5.2, a boot loop otherwise).
# It closes with the CI tooling image built and pushed.
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
# CR-6 in-VM report #14: this phase MUTATES the platform repo — the
# local clone may be behind the remote (a manual fix by the operator
# on GitHub during a resume). Synchronize BEFORE touching anything:
platform_repo_sync
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/aegis.key}"

# argo_sync comes from lib/common.sh (bug C run #8: the local
# definitions waited only for health — a race with operationState on
# re-runs; the canonical one waits for the operation's TERMINAL
# phase).

# ── 50.0 jenkins-admin (T2-A random — C10 settled by protocol) ─────
# gen_or_restore + no safekeeping pause (D11): the password is left
# encrypted in the store and in the KSOPS Secret — recoverable with
# the age key. For later interactive use: docs/protocols/
# rotation-checklist.md explains how to read it from the store.
secrets_workdir
ADMIN_PASS="$(gen_or_restore jenkins_admin_pass gen_password_b64)"
printf 'admin' > "$SECRETS_TMP/jenkins_admin_user"
make_enc_secret jenkins-admin jenkins-system \
    "$PLATFORM_DIR/k8s/base/platform/jenkins-secrets/secret-jenkins-admin.enc.yaml" \
    "username=$SECRETS_TMP/jenkins_admin_user" \
    "password=$ADMIN_PASS"

# class F audit: no || true to swallow a real failed commit:
git_commit_if_changes "$PLATFORM_DIR" "feat(jenkins): admin secret"
git_push_verified "$PLATFORM_DIR"

# ── 50.1 Secrets → chart (ORDER: 5.2) ─────────────────────────────
argo_sync jenkins-secrets
# F-B run #15: the sync died from transient DNS and the gate passed
# with the OLD Synced — it now demands the JUST-pushed revision:
argo_secrets_gate jenkins-secrets 300 \
    "$(git -C "$PLATFORM_DIR" rev-parse HEAD)"
gate "los-6-secrets" poll 180 5 bash -c "kubectl -n jenkins-system get secret \
  jenkins-admin hello-aegis-repo regcred-internal github-token \
  ops-stack-repo-ro github-webhook-hmac >/dev/null 2>&1"
# (D11: github-token + ops-stack-repo-ro replace the GitHub App.
#  cosign-signing-key arrives in phase 80; its entry is NOT in the
#  generator yet — phase 80 adds file+entry in the same commit. Here
#  the generator lists exactly the 6 that exist.)

argo_sync jenkins 900
# P1.4 audit 2026-07-18: Jenkins' boot was the SLOWEST legitimate step
# of the real run (~8 min: the init-container downloads the plugins
# over the operator's network) and its gate was a single, MUTE rollout
# status. wait_rollout: a generous wait with periodic evidence (E-1);
# on failure the diagnostic brings the init-container's logs — where
# the cause lives (a truncated plugin, the network, a dead mirror).
# Debt noted (VALIDACION §4): pre-baking the plugins into an image of
# our own would kill the download entirely:
gate_diag "jenkins-ready" \
  'kubectl -n jenkins-system get pods;
   kubectl -n jenkins-system logs jenkins-0 -c init --tail=25 2>/dev/null;
   kubectl -n jenkins-system get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 8' \
  wait_rollout jenkins-system sts/jenkins 1800

# ── 50.2 jobs-as-code: did the seeding run? (REAL verification) ────
# The jobs live in JCasC job-dsl inside values.yaml (D9). The gate is
# that the job EXISTS via the API, not "the chart says so". Auth
# through lib/jenkins.sh: netrc over stdin, password out of ALL argv
# (A27).
_job_exists() { jenkins_get "/job/$1/api/json" >/dev/null; }
gate "job-hello-aegis-mb-existe" retry_net 5 _job_exists hello-aegis-mb
# P1.9 audit: it was single-shot next to its sibling gate that had a
# retry — the job-dsl seeding runs async to the boot:
gate "job-ci-images-existe" retry_net 5 _job_exists ci-images

# ── 50.3 CI tooling image (aegis-ci-cosign) ────────────────────────
# In v2 building the image is NOT manual (doc 26 §16.9): it is a
# jenkins job 'ci-images' (also seeded by job-dsl) that builds
# ci-images/cosign/Containerfile and pushes to the registry. Triggered
# via the API (CSRF crumb in lib/jenkins.sh) + waiting for the result:
log_info "firing the ci-images build (buildah→push: a REAL pull/push of the registry)"
# F-C/F-D run #15: two consecutive MUTE FAILUREs (the cause lived in
# the console, never printed) and every retry cost re-running the
# phase by hand. jenkins_build_retry: it captures next BEFORE the POST
# (race #9), prints the tail of the console on failure, and re-fires
# ONLY if the failure has a transient NETWORK signature (the mobile
# network):
gate "ci-images-build-verde" jenkins_build_retry ci-images 1800 3

# ── 50.4 the defining gate: the image IS in the catalogue ──────────
# a real read of the registry (registry_creds: netrc+CA in tmpfs,
# without showing values). --resolve because the host does not resolve
# .svc (A30).
REG_HOST="$REGISTRY_HOST_INTERNAL"   # single source (P3 audit)
registry_creds "$REG_HOST" "$REGISTRY_CLUSTER_IP"
gate "aegis-ci-cosign-en-catalogo" retry_net 3 bash -c \
  "curl -fsS --netrc-file '$SECRETS_TMP/registry.netrc' \
     --cacert '$SECRETS_TMP/aegis-ca.crt' \
     --resolve '${REG_HOST%%:*}:5000:$REGISTRY_CLUSTER_IP' \
     'https://$REG_HOST/v2/aegis-ci-cosign/tags/list' \
   | jq -e '.tags | length > 0' >/dev/null"

log_ok "Jenkins alive with jobs-as-code (a disposable PVC), a random \
admin in the encrypted store, CI tooling built and verified in the registry"
