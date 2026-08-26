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
#
# EDGE=local (2026-08-26) — THE loss of the local profile, and the
# only link of the fifteen that has no replacement at all. The webhook
# is the one arrow that comes IN from the Internet: GitHub POSTs to
# jenkins.<domain>. Under a local edge that address is the host bridge
# on EDGE_BIND_IP (127.0.0.1 by default, or a private address of the
# LAN), and sslip.io resolves it publicly to exactly that — a number
# GitHub's senders cannot route to. There is no tunnel underneath and
# no public hostname to deliver to, so there is nothing to register
# (60.2) and no delivery to read (60.3). Those two gates have NO
# SUBJECT under this edge and SAY SO, recorded, never in silence.
# What is lost is not only the promptness: the HMAC/plugin link stops
# being MEASURED here — it is not that the receiver is fine, it is
# that under this edge nothing exercises it.
# The substitute the plan chose (04 §6) is polling: the derived job
# carries periodicFolderTrigger every 2m (phase 50), so the same push
# probe still proves the chain end to end — later, and because Jenkins
# went to look, not because GitHub knocked.
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
#
# This link DOES apply under both edges — the same question by a
# shorter path. With EDGE=local there is no Access in front and no
# tunnel underneath: the host bridge hands EDGE_BIND_IP:80/443 to
# traefik's fixed ClusterIP and the TLS is the internal CA's, already
# in the host's trust store (phase 40). edge_origin_responds finds no
# service token in the store and goes direct, saying so.
gate_diag "edge-jenkins-responde" \
  'kubectl -n infra-edge get pods 2>/dev/null | tail -n 3;
   kubectl -n jenkins-system get pods 2>/dev/null | tail -n 3' \
  retry_net 6 edge_origin_responds "https://jenkins.$ROOT_DOMAIN/login" '^(200|403)$'

# ── 60.2 hook registered + push probe ──────────────────────────────
# The hook is an object of the Cloudflare profile and of no other: it
# exists because the tunnel publishes jenkins.<domain> and GitHub can
# reach it. Under EDGE=local phase 15 has no address to give GitHub,
# so no hook is created and this gate has nothing to look at. It is
# NOT that the hook is missing by mistake — the distinction is the
# whole point of saying it out loud.
if [[ "${EDGE:-cloudflare}" == local ]]; then
    _gate_record "hook-jenkins-registrado" not-evaluated 0
    log_warn "GATE hook-jenkins-registrado has NO SUBJECT (recorded, not silent) — EDGE=local: there is no hook to register, because GitHub cannot deliver to jenkins.$ROOT_DOMAIN: it resolves to EDGE_BIND_IP, an address of this host, and there is no tunnel publishing it. The trigger under this edge is Jenkins POLLING the repository (periodicFolderTrigger, derived in phase 50)"
else
    WEBHOOK_URL="https://jenkins.$ROOT_DOMAIN/github-webhook/"
    # retry_net: with errexit ALIVE (F-A #15) a blink from gh would kill
    # the phase:
    HOOK_ID="$(retry_net 3 gh api "repos/$GH_OWNER/$APP_REPO/hooks" \
        --jq ".[] | select(.config.url==\"$WEBHOOK_URL\") | .id" | head -n1)"
    gate "hook-jenkins-registrado" test -n "$HOOK_ID"
fi
# P1.16 audit 2026-07-18: the multibranch's branch indexing is
# ASYNCHRONOUS — on a fresh instance the main job may not exist yet
# and the jenkins_next_build below died with no gate of its own. Wait
# for it with evidence (the scan's log carries the cause if it does
# not appear). Both edges: the indexing is Jenkins going out to
# GitHub, an arrow that LEAVES, and that one the local profile keeps.
_main_job_indexed() { jenkins_get "/job/hello-aegis-mb/job/main/api/json" >/dev/null 2>&1; }
gate_diag "job-main-indexado" \
  'kubectl -n jenkins-system logs sts/jenkins -c jenkins --since=10m 2>/dev/null | grep -iE "branch indexing|scan|hello-aegis" | tail -n 10' \
  poll 300 10 _main_job_indexed
# the build number is captured BEFORE the push (the lastBuild race
# #9, bug class C); retry_net on the push (mobile network):
NEXT_MB="$(jenkins_next_build hello-aegis-mb/job/main)"
if [[ "${EDGE:-cloudflare}" == local ]]; then
    log_info "e2e: push to the app's repo → Jenkins' periodic scan (up to 2m) → build #$NEXT_MB"
else
    log_info "e2e: push to the app's repo → hook delivery → build #$NEXT_MB"
fi
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
# flight (status null) is merely waited for.
#
# Under EDGE=local there are no deliveries to read: no hook, no POST,
# no attempt list. And with it goes the only thing that ever exercised
# the HMAC and the receiver plugin — that link is NOT measured on this
# edge, which is a WARNING and not an approval: nobody looked at it.
if [[ "${EDGE:-cloudflare}" == local ]]; then
    _gate_record "delivery-push-2xx" not-evaluated 0
    log_warn "GATE delivery-push-2xx has NO SUBJECT (recorded, not silent) — EDGE=local: there is no hook, so there is no delivery whose status_code to read. Consequence to keep in mind: the HMAC/plugin link (the receiver validating GitHub's signature) is NOT measured under this edge — it is not that it works, it is that nothing exercised it"
else
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
fi

# ── 60.4 the webhook CREATED the build (multibranch scan) ──────────
# a 2xx delivery but no build = the SCAN link (the scan's github-token
# credential, quiet period, the job): evidence separate from the
# HMAC's:
_build_triggered() {
    jenkins_get "/job/hello-aegis-mb/job/main/$NEXT_MB/api/json" \
        >/dev/null 2>&1
}
# The link is the same on both edges — did the push become a build? —
# but the cause behind it is not, and a gate that names the wrong
# cause sends the operator to look in the wrong place. Under
# EDGE=local nothing was delivered: what has to notice the push is the
# periodic scan (periodicFolderTrigger, 2m, derived in phase 50). It
# gets its own name and its own patience: a webhook is instantaneous,
# polling is not — 2× the interval plus the scan's own time.
if [[ "${EDGE:-cloudflare}" == local ]]; then
    # The name of a gate IS its contract, so the substitution is
    # declared and not left implicit: whoever reads gates.jsonl looking
    # for build-disparado-por-webhook on a local run has to find out
    # that there was no webhook, not find nothing at all.
    gate_no_subject "build-disparado-por-webhook" \
      "EDGE=local: GitHub cannot deliver to this edge, so no webhook fires a build. What notices a push here is the periodic scan, gated as build-por-sondeo-disparado"
    gate_diag "build-por-sondeo-disparado" \
      'jenkins_get "/job/hello-aegis-mb/job/main/api/json" 2>/dev/null | jq "{nextBuildNumber, inQueue: (.inQueueItem != null)}";
       jenkins_get "/job/hello-aegis-mb/config.xml" 2>/dev/null | grep -iE "periodicfoldertrigger|<spec>|interval" | head -n 5;
       log_warn "EDGE=local: the trigger here is the periodic scan, NOT a webhook. If the config above shows no periodicFolderTrigger, the job was derived WITHOUT polling (phase 50) and nothing will ever notice a push on this edge";
       kubectl -n jenkins-system logs sts/jenkins -c jenkins --since=10m 2>/dev/null | grep -iE "scan|branch indexing|hello-aegis" | tail -n 8' \
      poll 420 10 _build_triggered
else
    gate_diag "build-disparado-por-webhook" \
      'jenkins_get "/job/hello-aegis-mb/job/main/api/json" 2>/dev/null | jq "{nextBuildNumber, inQueue: (.inQueueItem != null)}";
       kubectl -n jenkins-system logs sts/jenkins -c jenkins --since=10m 2>/dev/null | grep -iE "scan|branch indexing|hello-aegis" | tail -n 8' \
      poll 300 10 _build_triggered
fi

# ── 60.5 the build ends GREEN (the lib's wait already diagnoses the
#     quota on every lap — run #11) ──────────────────────────────────
# The last link asks the same of both edges: whatever created the
# build, does the pipeline finish green? The name keeps saying webhook
# because that is the phase's contract under the edge that has one;
# what did the triggering is already told apart by 60.4's two gates.
gate "build-webhook-verde" jenkins_wait_build hello-aegis-mb/job/main 1800 "$NEXT_MB"

if [[ "${EDGE:-cloudflare}" == local ]]; then
    log_ok "CI verified end-to-end by LINKS: edge → periodic scan → \
green build. NOT verified on this edge: hook and 2xx delivery (there \
is no inbound path from GitHub — see the warnings above)"
else
    log_ok "Webhook verified end-to-end by LINKS: edge → 2xx delivery \
→ scan → green build"
fi
