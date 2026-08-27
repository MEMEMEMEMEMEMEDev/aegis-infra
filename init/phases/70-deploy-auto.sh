#!/usr/bin/env bash
# PHASE 70 — automatic deploy: tenant + Image Updater. The order is
# method (2026-07-03): deterministic tagging is ALREADY in the v2
# Jenkinsfile; ANTI-LOOP PROVEN BEFORE the write-back. The "dry-run
# sequence" died in #13 (H5: CRD v1.2.2 does NOT have dryRun — an
# imaginary schema): the brake is the ORDER (7.3) + the CR's
# dry-run=server against the live CRD (E10). Write-back method
# git/repocreds (the only one without TOFU — A38); the write key has
# been encrypted since phase 15.
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
# CR-6 in-VM report #14: this phase MUTATES the platform repo — the
# local clone may be behind the remote (a manual fix by the operator
# on GitHub during a resume). Synchronize BEFORE touching anything:
platform_repo_sync
secrets_workdir   # lib/jenkins.sh materializes the netrc in tmpfs

# argo_sync comes from lib/common.sh (bug C run #8: the local
# definitions waited only for health — a race with operationState on
# re-runs; the canonical one waits for the operation's TERMINAL
# phase).

# ── 70.1 tenant org-canary (the complete pattern A) ──────────────
argo_sync org-canary
gate "sa-default-con-pullsecret" bash -c \
  "kubectl -n org-canary get sa default \
     -o jsonpath='{.imagePullSecrets[0].name}' | grep -q regcred-internal"
gate "regcred-vivo" bash -c \
  "kubectl -n org-canary get secret regcred-internal >/dev/null"

# ── 70.2 the canary's first deploy (a REAL pull from the registry) ─
# H1 run #13: the seed's newTag assumed build #1 pushes main-000001,
# but the multibranch's #1 is the COSMETIC one (ABORTED without a
# push) — the first REAL tag was main-000002 and the canary asked for
# a nonexistent image (ImagePullBackOff "not found"). The source of
# truth is THE REGISTRY: we read the highest published main-* tag and
# align the overlay (a k8s-only commit → the anti-loop skips it):
REG_HOST="$REGISTRY_HOST_INTERNAL"   # single source (P3 audit)
registry_creds "$REG_HOST" "$REGISTRY_CLUSTER_IP"
# P1.15 audit 2026-07-18: "curl failed" ≠ "empty list". The old || true
# turned a network blink into a dead gate with the wrong diagnostic.
# The READ is demanded (retry + a die with the real cause); an empty
# filter result IS a legitimate verdict of the gate:
TAGS_JSON="$(retry_net 3 curl -fsS --max-time 30 \
    --netrc-file "$SECRETS_TMP/registry.netrc" \
    --cacert "$SECRETS_TMP/aegis-ca.crt" \
    "https://$REGISTRY_CLUSTER_IP:5000/v2/hello-aegis/tags/list")" || \
    die "could not READ the registry's catalogue (network/registry down) — this is NOT 'no tags'; check registry-system and re-run"
FIRST_TAG="$(jq -r '.tags[]?' <<< "$TAGS_JSON" \
  | grep -E '^main-[0-9]{6}$' | sort | tail -n1 || true)"
gate "tag-real-en-registry" test -n "$FIRST_TAG"
run_cmd retry_net 3 bash -c "cd \$(mktemp -d) && \
  git clone --depth 1 https://github.com/$GH_OWNER/$APP_REPO.git app && \
  cd app && \
  sed -i 's/newTag: main-[0-9]\{6\}/newTag: $FIRST_TAG/' \
      k8s/overlays/dev/kustomization.yaml && \
  if git diff --quiet; then echo 'newTag already aligned with the registry'; \
  else git commit -am 'chore(k8s): newTag = the first REAL tag in the registry' && \
       git push; fi"
argo_sync hello-aegis 600
# P1.14 audit: the repo-server may sync the OLD revision after the
# push — Synced only counts against the app repo's real HEAD (the F-B
# pattern extended; the sha is read from the remote because the clone
# used for the push above was ephemeral):
APP_HEAD="$(retry_net 3 git ls-remote \
    "https://github.com/$GH_OWNER/$APP_REPO.git" refs/heads/main)" || \
    die "could not read the remote HEAD of $APP_REPO (network)"
argo_secrets_gate hello-aegis 300 "${APP_HEAD%%$'\t'*}"
# H6 run #15 (defence in depth): "newTag already aligned" validated
# the kustomization — the INTENTION — but a leftover
# .argocd-source-*.yaml overrides the parameters and the EFFECTIVE
# image was another one (a nonexistent main-000009 →
# ImagePullBackOff). What ArgoCD really RESOLVED is validated: the tag
# of the rendered Deployment must exist in the registry's catalogue.
# Existence of the deploy first (pattern H4: existence→state):
gate "deploy-canary-existe" poll 180 5 bash -c \
  "kubectl -n org-canary get deploy hello-aegis >/dev/null 2>&1"
EFF_IMG="$(kubectl -n org-canary get deploy hello-aegis \
    -o jsonpath='{.spec.template.spec.containers[0].image}')"
printf '%s' "$TAGS_JSON" > "$SECRETS_TMP/tags.json"
# What ArgoCD resolved is checked against the registry ITSELF, in the
# shape it has. The DIGEST shape is the normal one here: the pipeline's
# write-digest.mjs pins the overlay by digest and nothing else, so the
# image reads name@sha256:… with no tag at all. Until 2026-08-27 this
# gate stripped the "@digest", took whatever followed the last ':' as
# the tag — on a digest-only image that is "5000/hello-aegis", the
# registry's PORT — looked it up in the catalogue, and failed a canary
# that was Running (first clean instance, VPS). A digest is checked by
# asking the registry for its manifest (HEAD); a tag, in the catalogue.
if [[ "$EFF_IMG" == *@sha256:* ]]; then
    EFF_REF="${EFF_IMG##*@}"
    EFF_HOW="manifest $EFF_REF answered by the registry"
    EFF_PROBE=(retry_net 3 curl -fsS -o /dev/null --max-time 30 -I \
        --netrc-file "$SECRETS_TMP/registry.netrc" \
        --cacert "$SECRETS_TMP/aegis-ca.crt" \
        -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
        "https://$REGISTRY_CLUSTER_IP:5000/v2/hello-aegis/manifests/$EFF_REF")
else
    EFF_REF="${EFF_IMG##*:}"
    EFF_HOW="tag $EFF_REF listed in the catalogue"
    EFF_PROBE=(bash -c "jq -e --arg t '$EFF_REF' '.tags[]? | select(. == \$t)' \
       '$SECRETS_TMP/tags.json' >/dev/null")
fi
log_info "effective image: $EFF_IMG → checking: $EFF_HOW"
gate_diag "tag-efectivo-en-registry" \
  'log_warn "the EFFECTIVE image of the Deployment is NOT in the registry — a leftover override (.argocd-source-*) trampling the pin? (H6 #15; the seeding in phase 12 should have purged it)";
   kubectl -n org-canary get deploy hello-aegis -o jsonpath="{.spec.template.spec.containers[0].image}"; echo;
   jq -r ".tags[]?" "$SECRETS_TMP/tags.json"' \
  "${EFF_PROBE[@]}"
# THIS is the defining gate of the registry→kubelet path (TLS+auth
# +mirror+/etc/hosts): a REAL pod pulled a REAL image. H7 #13: on
# failure the cause lives in events/describe — show it:
gate_diag "canary-corriendo" \
  'kubectl -n org-canary get events --sort-by=.lastTimestamp | tail -n 15;
   kubectl -n org-canary describe pod -l app=hello-aegis 2>/dev/null | tail -n 25' \
  bash -c "kubectl -n org-canary rollout status deploy/hello-aegis --timeout=300s >/dev/null"

# ── 70.3 anti-loop verified BEFORE the write-back (rule 7.3) ───────
# The v2 Jenkinsfile carries a structural detect-change (only k8s/** →
# SKIP). Gate: a commit that ONLY touches k8s/** must NOT produce a
# build with build/push stages:
log_info "anti-loop gate: a k8s-only commit => the pipeline must skip the build"
# the build number BEFORE the push (the lastBuild race #9: lastBuild's
# wfapi could describe the PREVIOUS build, not the probe's):
NEXT_PROBE="$(jenkins_next_build hello-aegis-mb/job/main)"
# sed exits 0 EVEN IF it matches nothing (a latent bug caught in the
# review after #4): on the FIRST run the seed does not have the
# antiloop-probe line → a "successful" sed with no change → commit -am
# died with "nothing to commit". grep really decides whether the line
# exists:
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
# a structural gate: the PROBE'S build must end green WITH the stages
# skipped. H3 run #13: /wfapi/ is provided by the pipeline-stage-view
# plugin, which is NOT installed (pipeline-stage-STEP and
# pipeline-stage-tags-metadata are OTHER plugins) → an eternal 404
# with the anti-loop WORKING PERFECTLY. It is validated against the
# core (/api/json, always present) + the build's console (the marker
# "skipped due to when conditional" — verified live in #13 on the
# probe's builds #4/#5):
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

# ── 70.4 the pipeline writes the DIGEST into git ───────────────────
#
# HERE LIVED the onboarding of argocd-image-updater: install the
# chart, wait for its CRD in the discovery, validate the CR with
# dry-run=server, add it to the kustomization in the same commit, and
# prove the whole cycle by waiting for its write-back. It was retired
# in #59 along with the component.
#
# Today's model is shorter and has fewer moving parts: the pipeline
# that BUILT the image already knows its digest and writes it into the
# overlay (the `desplegar` stage). The updater had to rediscover it by
# polling the registry, with a poller that hangs and a write-back that
# may never land — which is exactly what happened for months without
# anyone seeing it (#55).
#
# WHAT IS NOT LOST is the gate: that one proved the cycle really
# closed, and this one proves the same thing against the new
# mechanism. The canary's overlay is born with a MARKER digest of
# sixty-four zeros, obviously false on purpose; a real digest sitting
# there is the proof that the pipeline wrote it and that the commit
# landed in the repo.
#
# A real digest AND one DIFFERENT from the marker: checking only the
# format would let the zeros through, and they have the perfect shape
# of a digest.
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

log_ok "Tenant alive, canary deployed with a real pull, anti-loop \
verified, and the digest written by the pipeline itself"
