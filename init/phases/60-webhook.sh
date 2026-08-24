#!/usr/bin/env bash
# PHASE 60 — GitHub App → Jenkins webhook, end-to-end. The App and the
# HMAC already exist (phase 15); the receiver boots in phase 50 with
# the Secrets ALREADY in the cluster (a verified order: jenkins-secrets
# sync + gate BEFORE the sts — the plugin loads the HMAC at boot,
# lesson #12).
#
# REWRITTEN after #14 (Pattern B of the in-VM report, in its worst
# form): the single push→build gate coupled FOUR links — edge,
# delivery+HMAC, scan, build — and on failure it died MUTE with the
# diagnostic in a comment (mention ≠ use, H7). This phase's history:
# #10 desynchronized HMAC (a surviving hook), #11 hook deleted from a
# wrong diagnosis + quota, #12 HMAC with a \n. All different; all the
# SAME symptom with the coupled gate. Now each link has its gate and
# its evidence:
#   60.1 the edge answers for jenkins.<domain>       (tunnel/traefik)
#   60.2 hook registered + push probe                (GitHub)
#   60.3 the push's delivery ended 2xx               (HMAC/plugin)
#   60.4 the build EXISTS                            (scan/credential)
#   60.5 the build ends GREEN                        (pipeline/quota)
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
secrets_workdir   # lib/jenkins.sh materializes the netrc in tmpfs

# ── 60.1 the edge answers for Jenkins' host ────────────────────────
# /login is public (200) — it rules out a dead tunnel (the operator's
# mobile network — E-1), traefik without the IngressRoute, public DNS.
#
# #87 (2026-08-13): since Access sits in front of jenkins.<dom> (#76),
# a bare curl receives a 302 to Cloudflare's login. This gate demanded
# `^(200|403)$`, so it failed RED and stopped the phase — the mirror
# image of phase 35's failure, and the cheap one of the two: it breaks
# loudly and in plain sight. edge_origin_responds traverses Access with
# phase 25's service token and, if it CANNOT, says so for what it is
# (the origin was not measured) instead of as "Jenkins is not
# answering".
gate_diag "edge-jenkins-responde" \
  'kubectl -n infra-edge get pods 2>/dev/null | tail -n 3;
   kubectl -n jenkins-system get pods 2>/dev/null | tail -n 3' \
  retry_net 6 edge_origin_responds "https://jenkins.$ROOT_DOMAIN/login" '^(200|403)$'

# ── 60.2 hook registered + push probe ──────────────────────────────
WEBHOOK_URL="https://jenkins.$ROOT_DOMAIN/github-webhook/"
# retry_net: with errexit ALIVE (F-A #15) a blink from gh would kill
# the phase:
HOOK_ID="$(retry_net 3 gh api "repos/$GH_OWNER/$APP_REPO/hooks" \
    --jq ".[] | select(.config.url==\"$WEBHOOK_URL\") | .id" | head -n1)"
gate "hook-jenkins-registrado" test -n "$HOOK_ID"
# P1.16 audit 2026-07-18: the multibranch's branch indexing is
# ASYNCHRONOUS — on a fresh instance the main job may not exist yet
# and the jenkins_next_build below died with no gate of its own. Wait
# for it with evidence (the scan's log carries the cause if it does
# not appear):
_main_job_indexed() { jenkins_get "/job/hello-aegis-mb/job/main/api/json" >/dev/null 2>&1; }
gate_diag "job-main-indexado" \
  'kubectl -n jenkins-system logs sts/jenkins -c jenkins --since=10m 2>/dev/null | grep -iE "branch indexing|scan|hello-aegis" | tail -n 10' \
  poll 300 10 _main_job_indexed
# the build number is captured BEFORE the push (the lastBuild race
# #9, bug class C); retry_net on the push (mobile network):
NEXT_MB="$(jenkins_next_build hello-aegis-mb/job/main)"
log_info "e2e: push to the app's repo → hook delivery → build #$NEXT_MB"
run_cmd retry_net 3 bash -c "cd \$(mktemp -d) && \
  git clone --depth 1 https://github.com/$GH_OWNER/$APP_REPO.git app && \
  cd app && git commit --allow-empty -m 'ci: webhook e2e probe' && \
  git push"

# ── 60.3 the push's delivery ended 2xx ON GITHUB'S SIDE ────────────
# THIS is the gate that isolates HMAC/plugin (the equivalent of the
# webhook-redeliver-2xx that phase 35 already had for argocd and this
# phase never had). A 400 here with a green edge = the receiver is
# rejecting the signature: a desynchronized HMAC (was the store
# regenerated with Jenkins already up? the plugin loads the HMAC AT
# BOOT — restart the sts) or a JCasC binding. The evidence: the last
# deliveries with their status + the receiver's log:
# P1.5 audit 2026-07-18: GitHub does NOT re-deliver on its own — if
# the push landed on a 530 from the tunnel (the mobile network dropped
# right there), the old poll re-read the SAME dead delivery for 300s.
# Now, with the edge already green (60.1), a failed delivery is
# RE-DELIVERED (redeliver) every ~60s within the wait; a delivery in
# flight (status null) is merely waited for:
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
            log_warn "push delivery status=$code — redeliver #$redelivered (a 530/timeout from the edge is NOT re-delivered on its own)"
            if ! gh api -X POST \
                 "repos/$GH_OWNER/$APP_REPO/hooks/$HOOK_ID/deliveries/$did/attempts" \
                 >/dev/null 2>&1; then
                log_warn "the redeliver failed (gh/network) — it is retried on the next lap"
            fi
        fi
        sleep 10
    done
}
gate_diag "delivery-push-2xx" \
  'gh api "repos/$GH_OWNER/$APP_REPO/hooks/$HOOK_ID/deliveries" \
     --jq ".[0:5][] | \"\(.delivered_at) event=\(.event) status_code=\(.status_code) \(.status)\"" 2>/dev/null;
   log_warn "if status_code=400 with a green edge: desynchronized HMAC — the plugin loads the HMAC AT BOOT (lesson #12): if the store regenerated hmac_jenkins with Jenkins already up, kubectl -n jenkins-system rollout restart sts/jenkins and re-run with --from 60";
   kubectl -n jenkins-system logs sts/jenkins -c jenkins --since=10m 2>/dev/null | grep -iE "webhook|github" | tail -n 8' \
  _delivery_wait_2xx

# ── 60.4 the webhook CREATED the build (multibranch scan) ──────────
# a 2xx delivery but no build = the SCAN link (the scan's github-token
# credential, quiet period, the job): evidence separate from the
# HMAC's:
_build_triggered() {
    jenkins_get "/job/hello-aegis-mb/job/main/$NEXT_MB/api/json" \
        >/dev/null 2>&1
}
gate_diag "build-disparado-por-webhook" \
  'jenkins_get "/job/hello-aegis-mb/job/main/api/json" 2>/dev/null | jq "{nextBuildNumber, inQueue: (.inQueueItem != null)}";
   kubectl -n jenkins-system logs sts/jenkins -c jenkins --since=10m 2>/dev/null | grep -iE "scan|branch indexing|hello-aegis" | tail -n 8' \
  poll 300 10 _build_triggered

# ── 60.5 the build ends GREEN (the lib's wait already diagnoses the
#     quota on every lap — run #11) ──────────────────────────────────
gate "build-webhook-verde" jenkins_wait_build hello-aegis-mb/job/main 1800 "$NEXT_MB"

log_ok "Webhook verified end-to-end by LINKS: edge → 2xx delivery \
→ scan → green build"
