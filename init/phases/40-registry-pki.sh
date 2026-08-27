#!/usr/bin/env bash
# PHASE 40 — registry + internal PKI, "4 steps in strict order"
# (2026-07-02:46), WITH TLS FROM DAY ONE (a deliberate departure from
# the historical order that the source itself asks for:
# 2026-07-04:7).
# It contains the ONLY sudo block of the init (the CA onto the host,
# per node).
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

# ── 40.0 registry credentials (SINGLE ORIGIN — A27) ────────────────
# random password + htpasswd + THE 4 DERIVED regcreds IN THE SAME
# PROCESS (derive_htpasswd_and_regcreds makes a mismatch impossible):
secrets_workdir
REG_HOST="$REGISTRY_HOST_INTERNAL"   # single source (P3 audit)
# gen_or_restore: a re-run reuses the SAME password (bug 6 — if it
# regenerated, the new htpasswd would not match the old regcreds).
# No human pause for safekeeping: the password lives encrypted in the
# store (recoverable with the age key — D11: the only irreducible
# thing kept by hand is the age key):
PASS="$(gen_or_restore registry_pass gen_password_b64)"
derive_htpasswd_and_regcreds aegis-dev "$PASS" "$REG_HOST"

B="$PLATFORM_DIR/k8s/base"
make_enc_secret registry-htpasswd registry-system \
    "$B/registry-system/registry-htpasswd.enc.yaml" \
    "htpasswd=$SECRETS_TMP/htpasswd"
for pair in \
    "regcred-internal:jenkins-system:$B/platform/jenkins-secrets/secret-regcred-internal.enc.yaml" \
    "regcred-kyverno:kyverno:$B/kyverno/secret-regcred-kyverno.enc.yaml" \
    "regcred-internal:org-canary:$PLATFORM_DIR/k8s/organizations/org-canary/secret-regcred-internal.enc.yaml" \
    "regcred-internal:garage-system:$B/garage-system/secret-regcred-internal.enc.yaml"
do
    # garage-system: its secret-generator lists this file and, until
    # 2026-08-27, no phase wrote it — on the house machine it existed
    # from a hand-run `aegis secret`, on the first clean instance the
    # whole garage App failed to render (ksops: no such file) and no
    # tenant would ever have had a bucket. Check 145 derives this list
    # from the generators so the next namespace cannot be forgotten.
    IFS=: read -r name ns dest <<< "$pair"
    # --type MANDATORY (run #9, THE blocker of phase 60): without it,
    # make_enc_secret generates type OPAQUE and the kubelet IGNORES it
    # as an imagePullSecret ("no basic auth credentials" →
    # ImagePullBackOff of the cosign sidecar) even though the same
    # secret works mounted as a volume. dockerconfigjson serves BOTH
    # uses. (The previous comment claimed that "the generator sets the
    # type" — it was FALSE, nobody set it: A38, do not assert
    # unverified state.) A34: the type is IMMUTABLE — over a live
    # cluster with the old Opaque: kubectl delete secret + re-sync.
    make_enc_secret "$name" "$ns" "$dest" \
        --type kubernetes.io/dockerconfigjson \
        ".dockerconfigjson=$SECRETS_TMP/dockerconfig.json"
done
# the argocd-secrets generator entry IN THE SAME COMMIT as its
# .enc.yaml (the cosign pattern / temporal rule — run #4: a static
# entry for a file belonging to THIS phase broke the App's build in
# phase 35, and with it ALL of the App's secrets):
# ── the shared Garage's own credentials (rpc_secret + admin_token) ──
# garage-system's generator lists secret-garage-credentials.enc.yaml
# and, until 2026-08-27, NO phase wrote it: on the house machine it came
# from a hand-run `aegis secret create`; on the first clean instance
# the garage App never rendered (ksops: no such file), ArgoCD said
# Healthy about nothing, and no tenant would ever have had a bucket.
# `aegis secret create` creates IF MISSING and never regenerates —
# rotating these with the cluster up leaves the node unable to talk to
# itself, so a re-run of this phase must not touch them.
run_cmd aegis_exec secret create "$B/garage-system/secret-garage-credentials.enc.yaml"
gate "garage-credentials-cifradas" test -s "$B/garage-system/secret-garage-credentials.enc.yaml"
GEN_ARGO="$B/platform/argocd-secrets/secret-generator.yaml"
# H4 run #13: the grep -q by name matched the generator's COMMENT ("→
# phase 40 adds it") → the sed never ran → the secret was never born
# ("could not fetch secret" from the IU, 1 phase later). A STRUCTURAL
# guard (a list entry) + verification of the RESULT — never again a
# step swallowed by || true:
# HERE the Image Updater's regcred WAS ADDED to the argocd-secrets
# generator's list. It left with the component in #59: it was the
# credential the updater used to read the registry to discover new
# tags, and with no updater there is nobody to use it.
#
# The file name is NOT written here even though this is only a
# comment: check 4 of verify-static takes every literal mention of a
# *.enc.yaml in the phases as a PRODUCER, comments included. It
# over-detects on purpose —failing too much is safer than missing a
# producer— so naming it would make the verifier search forever for an
# entry that no longer exists.
# class F audit: no || true (an empty staged set = a no-op; a real
# failure with staged content = it dies HERE, not as a "broken
# kustomize" 2 gates later):
git_commit_if_changes "$PLATFORM_DIR" \
    "feat(registry): htpasswd + 5 atomically derived regcreds + garage credentials"
git_push_verified "$PLATFORM_DIR"

# ── 40.1 PKI + registry over GitOps (strict order) ─────────────────
argo_sync aegis-ca-issuer          # already synced in phase 35; idempotent
argo_sync registry 600
# Garage itself is NOT synced here: its image comes from the mirror,
# which phase 80 fills — on a fresh registry a sync now would sit in
# ImagePullBackOff until the mirror ran (measured on the second init of
# the rehearsal, 2026-08-27). Phase 80 syncs and MEASURES it once the
# image exists. What this phase guarantees is that its secrets do.
gate "registry-tls-secret" bash -c \
  "kubectl -n registry-system get secret registry-tls >/dev/null"
gate "registry-htpasswd-vivo" bash -c \
  "kubectl -n registry-system get secret registry-htpasswd >/dev/null"
# P3 audit 2026-07-18: REGISTRY_CLUSTER_IP from the conf is baked into
# cert/mirror/netrc/policy/probes and was NEVER validated against the
# REAL Service — a typo in the conf blew up as x509/timeout phases
# away. The source of truth is the cluster:
gate_diag "clusterip-coincide-con-el-service" \
  'kubectl -n registry-system get svc registry -o jsonpath="{.spec.clusterIP}"; echo " (conf: $REGISTRY_CLUSTER_IP)"' \
  bash -c "kubectl -n registry-system get svc registry \
     -o jsonpath='{.spec.clusterIP}' | grep -qx '$REGISTRY_CLUSTER_IP'"

# ── 40.2 the CA onto the HOST (sudo block; PER NODE on hetzner) ────
# The kubelet does not resolve .svc.cluster.local: a mirror by fixed
# ClusterIP + ca_file (2026-07-02:16-28). In v2 this is an ANSIBLE
# ROLE (settling the "pending" item of 2026-07-02:132), not a
# hand-written block:
log_info "role registry-host-trust (sudo): aegis-ca.pem + registries.yaml + restart k3s"
run_cmd kubectl -n cert-manager get secret aegis-internal-ca \
    -o jsonpath='{.data.ca\.crt}' > /dev/null   # existence, no dump
ansible_become_setup   # NOPASSWD => no prompt; otherwise, ONCE to tmpfs
# retry_net: the same contract as phase 20's playbooks (E-1 — ansible
# is idempotent by design, re-running is safe and it resumes):
run_cmd retry_net 2 "$PLATFORM_DIR"/ansible/.venv/bin/ansible-playbook \
    -i "$PLATFORM_DIR"/ansible/inventory/hosts.ini \
    "$PLATFORM_DIR"/ansible/playbooks/registry-host-trust.yml \
    "${ANSIBLE_BECOME_ARGS[@]}" \
    -e registry_cluster_ip="$REGISTRY_CLUSTER_IP"

# the host-trust gate (run #7, bug B): 40.2 had NO gate of its own —
# its failure (a censored ca.crt task) was deferred to phase 50's pull
# with a cryptic x509. The role leaves aegis-ca.pem + registries.yaml
# on the host (the local profile = this host; on hetzner the playbook
# itself validates them per node with failed_when):
gate "host-confia-en-el-CA" bash -c \
  "[[ -s /etc/rancher/k3s/aegis-ca.pem && -s /etc/rancher/k3s/registries.yaml ]]"

# ── 40.2b cluster DNS HEALTHY after the k3s restart (bug B) ────────
# The role's "restart k3s" restarts CoreDNS and the API server; if
# in-cluster DNS is left broken (outer layer: the forward to
# systemd-resolved's stub — solved by resolv-conf in phase 20; inner
# layer: the kubernetes plugin loses the watch after the restart), the
# first build of phase 50 fails to pull from the registry with a
# "lookup ...: Try again" 2 phases away. It is CUT here, with a
# diagnostic, verifying the REAL resolution of kubernetes.default AND
# of the registry (an ephemeral pod that exercises the whole DNS
# path):
DNS_PROBE="nslookup kubernetes.default.svc.cluster.local && \
nslookup registry.registry-system.svc.cluster.local"
# P1.8 audit: probe_reset BEFORE each attempt — if the kubectl run's
# attach expires, the pod stays and ALL the retries died with
# AlreadyExists (the retry cancelled itself out):
if ! retry_net 6 bash -c \
     "kubectl -n default delete pod dns-probe --ignore-not-found --now >/dev/null 2>&1; \
      kubectl -n default run dns-probe --rm -i --restart=Never \
        --image=busybox:1.36 --command -- sh -c '$DNS_PROBE' >/dev/null 2>&1"; then
    log_warn "in-cluster DNS does not resolve after the k3s restart (bug B run #7)"
    log_warn "  outer layer: did k3s start with resolv-conf? -> grep resolv-conf /etc/rancher/k3s/config.yaml"
    log_warn "  inner layer: CoreDNS' kubernetes plugin may have lost the watch — trying a rollout restart of CoreDNS"
    run_cmd kubectl -n kube-system rollout restart deploy/coredns
    # wait_rollout (E-1): after the k3s restart the node may be
    # re-pulling; 120s turned slow into failure on the mobile network:
    wait_rollout kube-system deploy/coredns 600
fi
gate "dns-cluster-sano" retry_net 6 bash -c \
  "kubectl -n default delete pod dns-probe --ignore-not-found --now >/dev/null 2>&1; \
   kubectl -n default run dns-probe --rm -i --restart=Never \
     --image=busybox:1.36 --command -- sh -c '$DNS_PROBE' >/dev/null 2>&1"

# ── 40.3 REAL pull gate (real capability, not a proxy) ─────────────
# a test pod pulling an image from the registry would validate the
# whole path; there is no image yet => the gate here is TLS+auth.
# P2.4 audit 2026-07-18: the old probe used -k — it did NOT validate
# the chain; a wrong cert passed green and blew up in the kubelet's
# pull 2 phases later with a cryptic x509. Now the probe mounts the
# ca.crt of the registry-tls Secret (cert-manager with a CA issuer
# includes it) and curl really DOES validate the chain. probe_reset
# per attempt (P1.8) + retry_net (E-1: the first run pulls alpine/curl
# and the attach may expire before the pull finishes):
TLS_OVR="{\"apiVersion\":\"v1\",\"spec\":{\"restartPolicy\":\"Never\",\
\"containers\":[{\"name\":\"tls-probe\",\"image\":\"alpine/curl\",\
\"args\":[\"-fsS\",\"--max-time\",\"20\",\"--cacert\",\"/ca/ca.crt\",\
\"-o\",\"/dev/null\",\"-w\",\"%{http_code}\",\"https://$REG_HOST/v2/\"],\
\"volumeMounts\":[{\"name\":\"ca\",\"mountPath\":\"/ca\",\"readOnly\":true}]}],\
\"volumes\":[{\"name\":\"ca\",\"secret\":{\"secretName\":\"registry-tls\",\
\"items\":[{\"key\":\"ca.crt\",\"path\":\"ca.crt\"}]}}]}}"
gate "registry-tls-real" retry_net 6 bash -c \
  "kubectl -n registry-system delete pod tls-probe --ignore-not-found --now >/dev/null 2>&1; \
   kubectl -n registry-system run tls-probe --rm -i --restart=Never \
     --image=alpine/curl --overrides='$TLS_OVR' 2>/dev/null | grep -q 401"
# 401 = the TLS chain VALIDATED against the CA + auth demanded (a
# curl -f against an invalid cert exits != 0 and prints no code). The
# real pull is proven by phase 50 (the first build) — that is the
# defining test.

log_ok "Registry with its own TLS + auth, host trusting the CA \
(Ansible role, per node), atomically derived regcreds"
