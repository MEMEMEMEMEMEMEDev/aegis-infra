#!/usr/bin/env bash
# PHASE 80 — supply-chain: Trivy → cosign (store, D11) → Kyverno with
# the ORDER AS THE MECHANISM (D5): kyverno-policies (Enforce) is the
# LAST thing enabled, after the first SIGNED image exists — on a fresh
# instance, Enforce before the first signature would reject the tenant
# itself (H-7, now codified).
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

# ── 80.1 Trivy server (the scan was already in the Jenkinsfile; up to
#     now the builds ran with the stage in tolerant mode) ───────────
argo_sync trivy-system
argo_sync trivy-server 600
# P1.8 audit: a prior delete per attempt — the --rm + retry cancelled
# itself out if the attach expired (an orphan pod → AlreadyExists).
# NETPOL RACE (integration run 2026-07-23, W-07 iter2): with
# trivy-system's default-deny, a JUST-created probe pod curls BEFORE
# kube-router programs its IP into the intra-ns ipset → connection
# refused (exit 7). The EXTERNAL retry does not help: it creates a NEW
# pod every time, which loses the race again. Fix: retry INSIDE the
# same pod (so kube-router programs it during the 1st sleep). See
# feedback-netpol-enforcement-vs-manifest: the manifest is correct,
# the enforcement (ipset) lags when the pod is created. The real
# clients (build pods) do NOT suffer this: they live for minutes
# before scanning.
gate "trivy-responde" retry_net 3 bash -c \
  "kubectl -n trivy-system delete pod trivy-probe --ignore-not-found --now >/dev/null 2>&1; \
   kubectl -n trivy-system run trivy-probe --rm -i --restart=Never \
     --image=alpine/curl -- \
     sh -c 'for i in 1 2 3 4 5 6 7 8 9 10 11 12; do \
       curl -fsS --max-time 5 http://trivy.trivy-system.svc.cluster.local:4954/healthz && exit 0; \
       sleep 3; done; exit 1' \
     >/dev/null"

# ── 80.2 cosign: signing authority WITHOUT a ceremony (D11) ────────
# The manual ceremony is gone: password and keypair go into the
# encrypted store — recoverable with the age key, which is THE only
# irreducible thing. gen_or_restore makes the re-run idempotent (bug
# 6: regenerating the keypair would invalidate the signatures already
# issued).
secrets_workdir
COSIGN_PASS="$(gen_or_restore cosign_pass gen_password_b64)"
# run #11 (a class): "does not decrypt" ≠ "does not exist" —
# regenerating the keypair over a mute sops would invalidate ALL the
# signatures issued. rc 2 = stop (store_rc_guard); rc 1 = it does not
# exist, generating is legal. No 2>&1: sops' error must be SEEN, not
# swallowed:
RC=0
restore_secret cosign_key cosign.key >/dev/null || RC=$?
store_rc_guard "$RC" cosign_key
if (( RC != 0 )); then
    gen_cosign_keypair "$SECRETS_TMP/cosign_pass"
    persist_secret cosign_key "$SECRETS_TMP/cosign.key"
    persist_secret cosign_pub "$SECRETS_TMP/cosign.pub"
else
    RC=0
    restore_secret cosign_pub cosign.pub >/dev/null || RC=$?
    store_rc_guard "$RC" cosign_pub
    (( RC == 0 )) || die "inconsistent store: cosign_key exists but cosign_pub is missing — it is not regenerated on its own (that would invalidate signatures); check .state-secrets/"
    log_info "cosign keypair restored from the store (previous signatures remain valid)"
fi
gate "cosign-material-completo" bash -c \
    "test -s '$SECRETS_TMP/cosign.key' && test -s '$SECRETS_TMP/cosign.pub'"

make_enc_secret cosign-signing-key jenkins-system \
    "$PLATFORM_DIR/k8s/base/platform/jenkins-secrets/secret-cosign-signing-key.enc.yaml" \
    "cosign.key=$SECRETS_TMP/cosign.key" \
    "cosign.password=$SECRETS_TMP/cosign_pass"
# the PUBLIC part is T1 → into the repo in the clear + inline in the
# policy:
run_cmd cp "$SECRETS_TMP/cosign.pub" \
    "$PLATFORM_DIR/k8s/base/platform/cosign/cosign.pub"
# inject the pub into the ClusterPolicy (placeholder __COSIGN_PUB__).
# CR-1 run #14: the global replace() also dumped the PEM INTO the
# header comment that mentioned the placeholder → broken top-level
# YAML → kustomize "missing Resource metadata" → the kyverno-policies
# App never synced → webhooks-scopeados died with no clue. EVERY
# multi-line injection goes through inject_placeholder (common.sh):
# non-comment lines only, a single occurrence, the real destination's
# indent, and it validates the resulting YAML BEFORE writing:
POL="$PLATFORM_DIR/k8s/base/kyverno-policies/clusterpolicy-require-aegis-signature.yaml"
if placeholder_pending "$POL" __COSIGN_PUB__; then
    run_cmd inject_placeholder "$POL" __COSIGN_PUB__ "$SECRETS_TMP/cosign.pub"
fi
gate "cosign-pub-inyectada" bash -c \
    "grep -q 'BEGIN PUBLIC KEY' '$POL' && ! grep -q '__COSIGN_PUB__' '$POL'"
# the generator entry IN THE SAME COMMIT as the .enc.yaml (A7 + atomic
# synchrony — the decision is noted in the generator):
GEN="$PLATFORM_DIR/k8s/base/platform/jenkins-secrets/secret-generator.yaml"
# H4 run #13 (structural guard — the grep by name matched comments; a
# latent instance of the same class that broke the IU's regcred in
# phase 40):
yaml_lists_file "$GEN" secret-cosign-signing-key.enc.yaml || \
    run_cmd sed -i \
      '/secret-github-webhook-hmac.enc.yaml/a\  - secret-cosign-signing-key.enc.yaml' \
      "$GEN"
gate "cosign-key-en-generator" \
    yaml_lists_file "$GEN" secret-cosign-signing-key.enc.yaml

# ORDER AS A REAL MECHANISM (run #12): the kyverno-policies App is
# automated — the comment "it syncs LAST" did not hold it back: the
# policy with the __COSIGN_PUB__ placeholder went live from phase 35
# and its webhook failurePolicy=Fail rejected phase 70's canary
# ("missing digest"; an EVALUATION failure blocks even if the action
# is Audit). The kustomization is born EMPTY (resources: []) and THIS
# phase adds the policy IN THE SAME COMMIT that injects the real pub —
# the same runtime-entry pattern as the generator above (checks
# 18/18b/39):
KPK="$PLATFORM_DIR/k8s/base/kyverno-policies/kustomization.yaml"
# H4 run #13: the original guard was a grep -q by name and the
# kustomization's COMMENT contains that name → it would have matched
# the comment and the entry would never have been added (the SAME
# class that broke the IU's regcred). A structural guard:
if ! yaml_lists_file "$KPK" clusterpolicy-require-aegis-signature.yaml; then
    run_cmd python3 - "$KPK" <<'EOF'
import sys
p = sys.argv[1]
t = open(p).read().replace(
    "resources: []",
    "resources:\n  - clusterpolicy-require-aegis-signature.yaml")
open(p, "w").write(t)
EOF
fi
gate "policy-en-kustomization" \
    yaml_lists_file "$KPK" clusterpolicy-require-aegis-signature.yaml
# Pattern A-2c (in-VM report #14): the error of a bad injection/entry
# was detected THREE links later (at ArgoCD's sync, where the message
# no longer points at the cause) — build the affected directory HERE,
# before the commit. This dir is PLAIN kustomize (argocd-secrets'
# cannot be built locally because of the KSOPS generator; its
# equivalent is the CR's dry-run=server in phase 70):
gate "kustomize-build-policies" bash -c \
  "kubectl kustomize '$PLATFORM_DIR/k8s/base/kyverno-policies' >/dev/null"

# inject aegis' CA into kyverno's values (T1; it did not exist until
# cert-manager issued it in phase 35 — the same pattern as
# __COSIGN_PUB__). global.caCertificates.data expects the PEM with the
# block's indentation:
# CR-2 run #14: the old injector took the indent of the FIRST line
# containing the placeholder — which was the values' COMMENT (indent
# 2) — and the PEM ended up outside the block scalar (indent 6) → helm
# template "did not find expected key" → ComparisonError → the kyverno
# App never synced. inject_placeholder ignores comments and takes the
# indent of the block's REAL line:
KYV="$PLATFORM_DIR/k8s/base/platform/kyverno/values.yaml"
CA_INJECTED_THIS_RUN=false
if placeholder_pending "$KYV" __AEGIS_CA_PEM__; then
    kubectl -n cert-manager get secret aegis-internal-ca \
        -o jsonpath='{.data.ca\.crt}' | base64 -d \
        > "$SECRETS_TMP/aegis-ca.pem"
    run_cmd inject_placeholder "$KYV" __AEGIS_CA_PEM__ "$SECRETS_TMP/aegis-ca.pem"
    CA_INJECTED_THIS_RUN=true
fi
gate "ca-inyectado-en-kyverno" bash -c \
    "grep -q 'BEGIN CERTIFICATE' '$KYV' && ! grep -q '__AEGIS_CA_PEM__' '$KYV'"

# class F audit: no || true to swallow a real failed commit:
git_commit_if_changes "$PLATFORM_DIR" \
    "feat(supply-chain): encrypted cosign key + pub and CA injected"
git_push_verified "$PLATFORM_DIR"
argo_sync jenkins-secrets    # now the generator completes the 7
# F-B #15: Synced only counts for the JUST-pushed revision:
argo_secrets_gate jenkins-secrets 300 \
    "$(git -C "$PLATFORM_DIR" rev-parse HEAD)"
gate "cosign-secret-vivo" poll 180 5 bash -c \
  "kubectl -n jenkins-system get secret cosign-signing-key >/dev/null 2>&1"

# ── 80.3 FIRST SIGNED IMAGE (the phase's hinge gate) ───────────────
REG_HOST="$REGISTRY_HOST_INTERNAL"   # single source (P3 audit)
registry_creds "$REG_HOST" "$REGISTRY_CLUSTER_IP"
# P1.8 in-VM report #14: every RESUME of this phase re-fired a signed
# build (~10 min) even when a valid signed image ALREADY existed —
# iterating over the phase cost 3x what it needed to. Real
# idempotence: if the registry's LAST tag verifies against cosign.pub,
# there is nothing to build. The digest ALWAYS comes from the
# REGISTRY's manifest (Docker-Content-Digest) — P3 audit: the
# post-build path that scraped Jenkins' console is dead; a single
# source for both paths. P1.15: the READ fails explicitly (retry +
# die) — "curl failed" ≠ "no tags":
registry_last_signed_candidate() {
    local tags_json
    tags_json="$(retry_net 3 curl -fsS --max-time 30 \
        --netrc-file "$SECRETS_TMP/registry.netrc" \
        --cacert "$SECRETS_TMP/aegis-ca.crt" \
        "https://$REGISTRY_CLUSTER_IP:5000/v2/hello-aegis/tags/list")" || \
        die "could not READ the registry's catalogue (network/registry down) — this is NOT 'no tags'"
    LAST_TAG="$(jq -r '.tags[]?' <<< "$tags_json" \
      | grep -E '^main-[0-9]{6}$' | sort | tail -n1 || true)"
    DIGEST=""
    if [[ -n "$LAST_TAG" ]]; then
        DIGEST="$(retry_net 3 curl -fsSI --max-time 30 \
            --netrc-file "$SECRETS_TMP/registry.netrc" \
            --cacert "$SECRETS_TMP/aegis-ca.crt" \
            -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
            "https://$REGISTRY_CLUSTER_IP:5000/v2/hello-aegis/manifests/$LAST_TAG" \
          | tr -d '\r' | awk 'tolower($1)=="docker-content-digest:"{print $2}')" || \
            die "the tag $LAST_TAG exists but I could not read its manifest (network/registry) — this is not an empty catalogue"
    fi
}
LAST_TAG="" DIGEST=""
registry_last_signed_candidate
if [[ -n "$DIGEST" ]] && DOCKER_CONFIG="$SECRETS_TMP/docker" cosign verify \
     --key "$PLATFORM_DIR/k8s/base/platform/cosign/cosign.pub" \
     --registry-cacert "$SECRETS_TMP/aegis-ca.crt" \
     --insecure-ignore-tlog=true \
     "$REGISTRY_CLUSTER_IP:5000/hello-aegis@$DIGEST" >/dev/null 2>&1; then
    log_ok "a VALID signed image is already in the registry ($LAST_TAG) — build skipped (resume idempotence, P1.8)"
else
    log_info "re-firing the canary's build to produce the first SIGNED image"
    NEXT_SIGN="$(jenkins_next_build hello-aegis-mb/job/main)"  # BEFORE the push (lastBuild race #9)
    run_cmd retry_net 3 bash -c "cd \$(mktemp -d) && \
      git clone --depth 1 https://github.com/$GH_OWNER/$APP_REPO.git app && \
      cd app && git commit --allow-empty -m 'ci: first signed build' && \
      git push"
    gate "build-firmado-verde" jenkins_wait_build hello-aegis-mb/job/main 1800 "$NEXT_SIGN"
    # P3 audit 2026-07-18: the digest is re-read from the registry's
    # MANIFEST (the same source as the idempotent path) — scraping
    # Jenkins' console was a fragile format of a build that on a
    # resume could be a different one:
    registry_last_signed_candidate
fi
# REAL verification of the signature (real capability, not "the stage
# says so" — and the gate runs ALWAYS, on the skip path too): it goes
# by direct IP (the host does not resolve .svc — A30; the registry's
# cert has the IP in its SANs). --insecure-ignore-tlog is NOT TOFU:
# the signature is fully verified against cosign.pub — only the public
# transparency log is skipped, and it was never used
# (--tlog-upload=false in the pipeline, a private registry).
gate "digest-extraido" test -n "$DIGEST"
gate "firma-verificada-real" bash -c \
  "DOCKER_CONFIG='$SECRETS_TMP/docker' cosign verify \
     --key '$PLATFORM_DIR/k8s/base/platform/cosign/cosign.pub' \
     --registry-cacert '$SECRETS_TMP/aegis-ca.crt' \
     --insecure-ignore-tlog=true \
     '$REGISTRY_CLUSTER_IP:5000/hello-aegis@$DIGEST' >/dev/null"

# ── 80.4 Kyverno: install → implicit Audit → Enforce at the end ────
argo_sync kyverno-base
argo_sync kyverno 600
# P1.1 audit 2026-07-18 (CONFIRMED LIVE): the CA is mounted by subPath
# — the kubelet does NOT refresh subPath mounts when the
# Secret/ConfigMap changes. If the controllers were already running
# when THIS run injected the CA, they keep the old/nonexistent one in
# memory → x509 when verifying against the registry → fail-closed deny
# → a 920s gate expired with a distant diagnostic. After a NEW
# injection: a rollout restart of ALL kyverno deploys + a real wait
# (the golden anti-class-D rule: config of a live pod ⇒ restart or
# checksum):
if [[ "$CA_INJECTED_THIS_RUN" == "true" ]]; then
    log_info "CA injected on THIS run — rollout restart of Kyverno's controllers (subPath does not refresh on its own)"
    run_cmd bash -c "kubectl -n kyverno get deploy -o name \
        | xargs -r -n1 kubectl -n kyverno rollout restart"
    while IFS= read -r d; do
        gate "kyverno-restart-${d##*/}" wait_rollout kyverno "$d" 600
    done < <(kubectl -n kyverno get deploy -o name)
fi

# A v1.1 applied to Kyverno (same pattern, another provider): the
# ClusterPolicy is governed by Kyverno's admission webhook — which has
# just restarted because of the CA. "App Healthy" does not prove it is
# serving; the ENDPOINTS do. Without this, the sync below can die with
# the same "no endpoints available" that killed phase 35 in v1.1:
gate "kyverno-webhook-sirviendo" \
    webhook_serving kyverno kyverno-svc 300

# THE LAST App of the init (D5): the Enforce policy comes in once a
# signed + verified image already exists:
argo_sync kyverno-policies
# P1.14: Synced only counts for the revision of THIS phase's commit:
argo_secrets_gate kyverno-policies 300 \
    "$(git -C "$PLATFORM_DIR" rev-parse HEAD)"
# P1.9 audit: it was single-shot over an ASYNCHRONOUS step (the
# controller admits the policy and only then sets Ready):
gate "policy-ready" poll 180 5 bash -c \
  "kubectl get clusterpolicy require-aegis-signature \
     -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null \
   | grep -q True"
# class D audit: this gate ran BEFORE the policy's sync — the scoped
# ValidatingWebhookConfiguration is GENERATED by Kyverno once the
# policy exists; checking it earlier was asking for the effect before
# the cause. Now: after policy-ready, with poll:
gate "webhooks-scopeados" poll 180 5 bash -c \
  "kubectl get validatingwebhookconfigurations -o yaml 2>/dev/null \
   | grep -q 'org-canary'"
# (A44: the webhook's namespaceSelector IS the blast radius of the
#  failurePolicy Fail — verify the generated object, not the policy)

# ── 80.5 the supply-chain's final gate (3.E.3's, codified) ─────────
# CR-2-poll run #14: after policy-ready the Deployment still
# references the LAST PRE-signature tag (the IU has not yet bumped to
# 80.3's signed build) — an immediate restart produces legitimately
# DENIED pods (a race that unjams itself but dirties the gate). Wait
# for the IU→ArgoCD cycle to deploy the signed image (Kyverno's
# autogen mutates the Deployment to a digest at admission):
gate_diag "canary-pineado-a-digest" \
  'kubectl -n org-canary get deploy hello-aegis \
     -o jsonpath="{.spec.template.spec.containers[0].image}"; echo;
   kubectl -n argocd logs deploy/argocd-repo-server --since=15m 2>/dev/null | tail -n 20' \
  poll 900 15 bash -c \
  "kubectl -n org-canary get deploy hello-aegis \
     -o jsonpath='{.spec.template.spec.containers[0].image}' \
   | grep -q '@sha256:'"
# positive: the canary's rollout admitted and MUTATED to a digest.
# Pattern B (in-VM report #14) here too: on failure it must be
# possible to DISTINGUISH "denied by Kyverno" from "rollout timeout" —
# the ns' events and the deploy's describe carry the real reason:
run_cmd kubectl -n org-canary rollout restart deploy/hello-aegis
# Finding B v1.0: the restart triggers one deployment and Kyverno's
# mutation (it pins the digest into the template) triggers a SECOND —
# in that window 3+ ReplicaSets coexist with pods being born and
# dying. The old gate measured at 5s with "items[0] of the namespace"
# and found an OLD pod (its own evidence showed the new pod Running
# and pinned — a verdict contradicted by its evidence). Convergence
# family, instance #5. Now: EXISTENCE→STABILITY (k8s_converged
# absorbs the cascade by re-waiting each rollout) → measure ONLY the
# pods of the CURRENT RS (deploy_current_pods_ok):
gate_diag "positivo-rollout-convergido" \
  'kubectl -n org-canary get rs 2>/dev/null;
   kubectl -n org-canary get pods 2>/dev/null;
   kubectl -n org-canary get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 10' \
  k8s_converged org-canary deploy/hello-aegis 300
_positive_ok() {
    deploy_current_pods_ok org-canary hello-aegis \
      '.status.phase == "Running" and (.spec.containers[0].image | test("@sha256:"))'
}
gate_diag "positivo-admitido-y-digest" \
  'kubectl -n org-canary get pods -o wide 2>/dev/null | tail -n 6;
   kubectl -n org-canary get deploy hello-aegis -o jsonpath="{.spec.template.spec.containers[0].image}" 2>/dev/null; echo;
   if kubectl -n org-canary get pods -o jsonpath="{range .items[*]}{.spec.containers[0].image}{\"\n\"}{end}" 2>/dev/null | grep -q "@sha256:"; then
     log_warn "POSSIBLE TIMING, not a real failure: there are pods with the image pinned to a digest — the expected state is PRESENT but the cascade of deployments did not converge (B v1.0); a resume usually passes in seconds";
   fi' \
  poll 120 5 _positive_ok
# netpol (W-07 / P-D): the tenant is ISOLATED — from the canary
# (already running, signed, alpine with wget) the pipeline is NOT
# reachable. jenkins is UP; the tenant's egress only allows DNS, so
# the connect to :8080 must TIME OUT. If it connects, the netpol does
# not isolate:
_netpol_isolated() {
    # a test exec (a live exec channel + a Ready pod) through the
    # Deployment — kubectl picks the pod, no items[0] of the namespace
    # (check 72):
    kubectl -n org-canary exec deploy/hello-aegis -- true 2>/dev/null \
        || { echo "could not exec into the canary (NotReady?) — this is not a netpol verdict"; return 1; }
    # a real connect: jenkins UP, the tenant's egress DNS-only → it
    # must fail. If it connects, the netpol does NOT isolate:
    if kubectl -n org-canary exec deploy/hello-aegis -- \
         wget -q -T 4 -O /dev/null http://jenkins.jenkins-system:8080 2>/dev/null; then
        echo "FAILURE: the canary reached jenkins:8080 — the netpol does NOT isolate the tenant's egress"
        return 1
    fi
    return 0   # a timeout with a live exec = isolated (what is expected)
}
gate_diag "netpol-tenant-aislado" \
  'kubectl -n org-canary get netpol 2>/dev/null;
   kubectl -n org-canary get pod -l app=hello-aegis 2>/dev/null' \
  _netpol_isolated
# the final gate's probes (CR-3/CR-4 run #14): in org-canary a BARE
# pod is rejected by PSS restricted or by the ResourceQuota EVEN IF
# Kyverno intercepted nothing (a false green for the negative), and in
# jenkins-system the strict quota rejects it BEFORE it reaches Kyverno
# (a false red for the scope). The probes are PSS/quota-compliant —
# the ONLY non-compliant thing about the negative is the signature:
PROBE_RES='"resources":{"requests":{"cpu":"10m","memory":"16Mi"},"limits":{"cpu":"50m","memory":"32Mi"}}'
PROBE_SC='"securityContext":{"runAsNonRoot":true,"allowPrivilegeEscalation":false,"seccompProfile":{"type":"RuntimeDefault"},"capabilities":{"drop":["ALL"]}}'
NEG_IMG="$REGISTRY_CLUSTER_IP:5000/hello-aegis:doesnotexist"
NEG_OVR="{\"apiVersion\":\"v1\",\"spec\":{\"containers\":[{\"name\":\"unsigned-probe\",\"image\":\"$NEG_IMG\",\"command\":[\"true\"],$PROBE_SC,$PROBE_RES}]}}"
# negative: an UNSIGNED image REJECTED **BY THE POLICY** — the assert
# is over the MESSAGE of the deny (verified 3x live in #14: the real
# deny cites require-aegis-signature; PSS or quota cite something
# else).
# P1.17 audit 2026-07-18: a deny from "context deadline"/"failed
# calling webhook" of a webhook that JUST came up (or that was just
# restarted by the CA fix) is TRANSIENT — dying there gave the wrong
# diagnostic on the init's last gate. Up to 3 attempts; only the
# POLICY's deny (or an improper admission) are final verdicts:
NEG_OUT="" NEG_OK=false
for _i in 1 2 3; do
    probe_reset org-canary unsigned-probe
    if NEG_OUT="$(kubectl -n org-canary run unsigned-probe --restart=Never \
          --image="$NEG_IMG" --overrides="$NEG_OVR" 2>&1)"; then
        # best-effort cleanup on the way to the die (output to stderr,
        # not swallowed):
        kubectl -n org-canary delete pod unsigned-probe \
            --ignore-not-found >&2 || true
        _gate_record "negativo-rechazado" fail 0
        die "GATE negativo-rechazado FAILED — the pod with an UNSIGNED image was ADMITTED into org-canary"
    fi
    if grep -q 'require-aegis-signature' <<< "$NEG_OUT"; then
        NEG_OK=true
        break
    fi
    if grep -qiE 'context deadline|failed calling webhook|connection refused|no endpoints available' <<< "$NEG_OUT"; then
        log_warn "negativo-rechazado: the webhook is not answering yet (transient after the restart, attempt $_i/3) — waiting 20s"
        sleep 20
        continue
    fi
    break   # a rejection unrelated to the policy and with no transient signature: a verdict
done
if [[ "$NEG_OK" == "true" ]]; then
    _gate_record "negativo-rechazado" pass 0
    log_ok "GATE negativo-rechazado (the deny cites require-aegis-signature — not PSS, not quota)"
else
    printf '%s\n' "$NEG_OUT" >&2
    _gate_record "negativo-rechazado" fail 0
    die "GATE negativo-rechazado FAILED — the rejection was NOT signed by the policy (PSS/quota covering for Kyverno? CR-4 #14; above: the real message)"
fi
# DENY-BY-DEFAULT negative (W-04): an image with ANOTHER name and
# ANOTHER registry, unsigned. With the old allowlist (hello-aegis*) it
# GOT IN without verification; with imageReferences:* it must be
# REJECTED citing the policy — it is THE gate that proves there is no
# longer an allowlist by name. The same anti-transient pattern (P1.17)
# as the negative above:
DBD_IMG="docker.io/library/nginx:1.27"
DBD_OVR="{\"apiVersion\":\"v1\",\"spec\":{\"containers\":[{\"name\":\"dbd-probe\",\"image\":\"$DBD_IMG\",\"command\":[\"true\"],$PROBE_SC,$PROBE_RES}]}}"
DBD_OUT="" DBD_OK=false
for _i in 1 2 3; do
    probe_reset org-canary dbd-probe
    if DBD_OUT="$(kubectl -n org-canary run dbd-probe --restart=Never \
          --image="$DBD_IMG" --overrides="$DBD_OVR" 2>&1)"; then
        kubectl -n org-canary delete pod dbd-probe --ignore-not-found >&2 || true
        _gate_record "negativo-deny-by-default" fail 0
        die "GATE negativo-deny-by-default FAILED — nginx (ANOTHER name/registry, UNSIGNED) was ADMITTED: the policy is still an allowlist, not deny-by-default"
    fi
    if grep -q 'require-aegis-signature' <<< "$DBD_OUT"; then DBD_OK=true; break; fi
    if grep -qiE 'context deadline|failed calling webhook|connection refused|no endpoints available' <<< "$DBD_OUT"; then
        log_warn "negativo-deny-by-default: transient webhook (attempt $_i/3) — 20s"; sleep 20; continue
    fi
    break
done
if [[ "$DBD_OK" == "true" ]]; then
    _gate_record "negativo-deny-by-default" pass 0
    log_ok "GATE negativo-deny-by-default (unsigned nginx REJECTED citing the policy — there is no allowlist by name)"
else
    printf '%s\n' "$DBD_OUT" >&2
    _gate_record "negativo-deny-by-default" fail 0
    die "GATE negativo-deny-by-default FAILED — the rejection of nginx was NOT signed by the policy (above: the real message)"
fi
# scope: outside org-canary it does NOT apply — an unsigned public
# image MUST be admitted in jenkins-system (if Kyverno rejects it, the
# webhook's namespaceSelector is wrong and this gate FAILS).
# Only resources (the quota demands limits); WITHOUT a restricted
# securityContext: busybox runs as root and runAsNonRoot would kill it
# at runtime — jenkins-system is not restricted and the gate is about
# ADMISSION:
# busybox PINNED (P3 audit: it was the only probe without a pin) +
# probe_reset (P1.8):
SCOPE_OVR="{\"apiVersion\":\"v1\",\"spec\":{\"containers\":[{\"name\":\"scope-probe\",\"image\":\"busybox:1.36\",\"command\":[\"true\"],$PROBE_RES}]}}"
probe_reset jenkins-system scope-probe
gate_diag "scope-fuera-admite" \
  'kubectl -n jenkins-system get events --sort-by=.lastTimestamp | tail -n 10' \
  bash -c "kubectl -n jenkins-system run scope-probe --rm -i --restart=Never \
     --image=busybox:1.36 --overrides='$SCOPE_OVR' >/dev/null"
# W-08 / EV-03: the force-kill fail-closed gates VERIFY the product's
# strongest property (Kyverno down → org-canary REJECTS). They are
# DISRUPTIVE (they crash the admission controller), so they do NOT run
# on every bootstrap; they DO in the validation with
# AEGIS_VALIDATE_FAILCLOSED=1. When they do NOT run they are RECORDED
# as skipped — NEVER silently (EV-08): no report may claim fail-closed
# if the gate did not measure (EV-03).
_failclosed_gates() {
    # a HARD crash (SIGKILL --force, NOT graceful: a graceful shutdown
    # removes Kyverno's webhooks and would prove nothing).
    # failurePolicy Fail + a dead webhook: org-canary (inside the
    # namespaceSelector) REJECTS; argocd (outside) ADMITS — a bounded
    # blast radius (3.E.3 t4/5).
    log_warn "fail-closed: killing Kyverno's admission controller HARD (disruptive, it recovers on its own)"
    kubectl -n kyverno delete pod -l app.kubernetes.io/component=admission-controller \
        --grace-period=0 --force >&2 || true
    local i
    for i in $(seq 1 30); do   # wait for the endpoint to DISAPPEAR
        kubectl -n kyverno get endpoints kyverno-svc \
            -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | grep -q . || break
        sleep 2
    done
    # guard: if the webhook is still alive, the kill did not take — it
    # is NOT a fail-closed verdict (it would be a false fail-open from
    # a bad delete selector):
    if kubectl -n kyverno get endpoints kyverno-svc \
         -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | grep -q .; then
        _gate_record "failclosed-org-canary-rechaza" fail 0
        die "GATE fail-closed: could NOT bring down Kyverno's webhook (the endpoint is alive after the kill) — check the delete's selector, this is not a verdict"
    fi
    local fc_ovr out
    fc_ovr="{\"apiVersion\":\"v1\",\"spec\":{\"containers\":[{\"name\":\"fc-probe\",\"image\":\"$DBD_IMG\",\"command\":[\"true\"],$PROBE_SC,$PROBE_RES}]}}"
    # (1) org-canary REJECTS because of the downed webhook (real
    #     fail-closed). The probe is PSS-compliant → it passes PSS and
    #     REACHES the dead webhook:
    if out="$(kubectl -n org-canary run fc-probe --restart=Never \
              --image="$DBD_IMG" --overrides="$fc_ovr" 2>&1)"; then
        kubectl -n org-canary delete pod fc-probe --ignore-not-found >&2 || true
        _gate_record "failclosed-org-canary-rechaza" fail 0
        die "GATE fail-closed FAILED — with Kyverno DOWN org-canary ADMITTED a pod: that is fail-OPEN, not fail-closed"
    fi
    grep -qiE 'failed calling webhook|context deadline|no endpoints|connection refused' <<< "$out" \
        || { printf '%s\n' "$out" >&2; _gate_record "failclosed-org-canary-rechaza" fail 0
             die "GATE fail-closed FAILED — org-canary rejected but NOT because of the downed webhook (PSS/quota? message above)"; }
    _gate_record "failclosed-org-canary-rechaza" pass 0
    log_ok "GATE failclosed-org-canary-rechaza (Kyverno down → org-canary REJECTS because of the webhook — REAL fail-closed)"
    # (2) argocd ADMITS (outside the selector → the platform does not
    #     freeze):
    if out="$(kubectl -n argocd run fc-probe --restart=Never \
              --image=busybox:1.36 --command -- true 2>&1)"; then
        kubectl -n argocd delete pod fc-probe --ignore-not-found >&2 || true
        _gate_record "failclosed-argocd-admite" pass 0
        log_ok "GATE failclosed-argocd-admite (Kyverno down → argocd ADMITS — a bounded blast radius)"
    else
        printf '%s\n' "$out" >&2
        _gate_record "failclosed-argocd-admite" fail 0
        die "GATE fail-closed FAILED — with Kyverno down argocd did NOT admit: the namespaceSelector does not bound anything (the whole platform would freeze)"
    fi
    # recovery: the Deployment recreates the admission controller:
    log_info "fail-closed: waiting for Kyverno to recover (rollout of the admission controller)"
    wait_rollout kyverno deployment.apps/kyverno-admission-controller 300 \
        || log_warn "Kyverno's admission controller did not come back within 300s — CHECK before using the cluster further"
}
if [[ "${AEGIS_VALIDATE_FAILCLOSED:-}" == "1" || "${AEGIS_VALIDATE_FAILCLOSED:-}" == "true" ]]; then
    _failclosed_gates
else
    # Through the ONE helper (lib/common.sh), which is what every phase
    # uses since 2026-08-26 to say "this gate had nothing to look at".
    # Until then this phase spoke its own dialect —_gate_record with the
    # word `skipped`— and check 083 grepped for that literal: one word
    # here, another in the phases the local edge added, and a check tied
    # to whichever of the two it had seen first.
    for _fc in failclosed-org-canary-rechaza failclosed-argocd-admite; do
        gate_no_subject "$_fc" \
            "AEGIS_VALIDATE_FAILCLOSED is not set: the fail-closed property is NOT measured (EV-03). Run the validation with AEGIS_VALIDATE_FAILCLOSED=1 to exercise it"
    done
fi

# ── 80.6 the third parties come in through the same door ──────────
# mirror-images needs everything this phase just proved: the trivy
# server (80.1) and the cosign key (80.2). Until 2026-08-27 nobody
# fired it: the job did not even exist in the seed's job-dsl, so a
# fresh instance whose first tenant declared a postgres was born with
# services.yaml pointing at an internal image that nobody had ever
# pushed — ImagePullBackOff, and `aegis data restore` with nowhere to
# restore to (R-21 in the record). It is a GATE and not a courtesy: a
# third-party image that does not pass the scan does not get in, and
# an init that ends green over an empty registry would be the silence
# this tree exists to make impossible. The job keeps going past a
# broken image and lists them all at the end, so one red here names
# every image that needs a newer tag — not just the first.
gate "mirror-images-build-verde" jenkins_build_retry mirror-images 2700 2

log_ok "SUPPLY-CHAIN COMPLETE: blocking scan + signature + bounded \
fail-closed Enforce. The init is done: the v2 platform end to end."
