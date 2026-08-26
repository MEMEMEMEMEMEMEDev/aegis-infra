#!/usr/bin/env bash
# PHASE 35 — handover to GitOps: root App + syncs in ORDER (the order
# IS the contract — ADR-0015:64-74 and D5). In v2 the WHOLE platform
# plane comes in through here (D6): cert-manager, PKI, traefik,
# cloudflared… none of it was pre-installed by tofu, so there is no
# adoption — it is a clean deployment in sequence.
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"

# argo_sync comes from lib/common.sh (bug C run #8: the local
# definition waited only for health — a race with operationState on
# re-runs; the canonical one waits for the TERMINAL phase of the new
# operation).

# ── AppProjects BEFORE root (W-06 / class C1) ──────────────────────
# root and the Apps reference aegis-bootstrap/platform/tenant; the
# projects have to exist first or the App is left "project not found".
# Imperative bootstrap infrastructure (like the D2 Secrets), outside
# the App-of-Apps path so that root does not manage them:
#
# TWO files, and both are needed:
#   appprojects.yaml           the substrate (bootstrap, platform) and
#                              what does not come from a contract
#                              (canary, inherited ones)
#   appprojects-tenants.yaml   DERIVED by `aegis org` from the
#                              contracts that declare a repo
# Without the second one, the organizations' Applications start up and
# ArgoCD leaves them at "project not found" (#19).
run_cmd kubectl apply -f "$PLATFORM_DIR/k8s/bootstrap/appprojects.yaml"
# The derived one may be EMPTY and that is correct: a freshly started
# instance has no contracts yet. `kubectl apply` over a file with no
# objects exits 1 ("no objects passed to apply") and would kill the
# phase. The question is asked structurally (yaml_has_docs), not with
# a grep of the kind: the file's header names it in prose.
if yaml_has_docs "$PLATFORM_DIR/k8s/bootstrap/appprojects-tenants.yaml"; then
    run_cmd kubectl apply -f "$PLATFORM_DIR/k8s/bootstrap/appprojects-tenants.yaml"
else
    log_info "appprojects-tenants.yaml has no documents: 0 contracts in orgs/, nothing to derive"
fi
gate "appprojects-creados" bash -c \
  "kubectl get appproject -n argocd aegis-bootstrap aegis-platform aegis-tenant-canary >/dev/null 2>&1"
# The gate above looks at the three FIXED ones. The derived ones are
# checked against the file and not against a list written here:
# enumerating them would be a fourth place to remember to add the new
# organization to, which is exactly what #19 came to remove.
gate "appprojects-derivados" bash -c '
  missing=""
  for p in $(grep -oP "(?<=^  name: )aegis-tenant-\S+" \
             "'"$PLATFORM_DIR"'/k8s/bootstrap/appprojects-tenants.yaml" 2>/dev/null); do
      kubectl get appproject -n argocd "$p" >/dev/null 2>&1 || missing="$missing $p"
  done
  [[ -z "$missing" ]] || { echo "derived AppProjects that were not created:$missing"; exit 1; }'

# ── root (MANUAL sync always — ADR-0012) ───────────────────────────
run_cmd kubectl apply -f "$PLATFORM_DIR/k8s/argocd-apps/root.yaml"
argo_sync root 120

# ── FORCED ORDER: PROVIDERS BEFORE CONSUMERS ───────────────────────
# Finding A v1.1 (INVERTED webhook dependency, deterministic on a cold
# cluster): argocd-secrets synced FIRST and contained a Certificate —
# whose admission webhook is provided by cert-manager, which synced
# AFTERWARDS → "no endpoints available for service
# cert-manager-webhook" → phase 35 down. It only looked intermittent
# because the root App's auto-sync sometimes won the race.
# The new order puts the PROVIDERS (CRDs + webhooks) first; none of
# them depends on argocd-secrets' Secrets, so moving them earlier
# costs nothing. The constraint that motivated the old order is kept
# intact: argocd-secrets STILL goes before argocd-self (otherwise the
# $github-webhook:token pointer stays literal and the webhook gives
# 400 until the restart — ADR-0015).

# 1. cert-manager: the CRDs + the webhook that governs every
#    Certificate.
argo_sync cert-manager 600
# the App being Healthy is NOT enough (A v1.1): the signal is that the
# webhook's Service has ENDPOINTS — cert-manager takes ~1-2 min from
# scratch and in that window EVERY Certificate is rejected:
gate "cert-manager-webhook-sirviendo" \
    webhook_serving cert-manager cert-manager-webhook 300

# 2. internal PKI (ClusterIssuers + the aegis-ca-trust Certificate,
#    which lives HERE since fix A: next to the issuer it references):
argo_sync aegis-ca-issuer
argo_sync cert-manager-issuers      # LE staging+prod (DNS-01)

# 3. traefik: installs the IngressRoute CRD that argocd-secrets uses.
argo_sync traefik 600               # trustedIPs baked in (A31)

# 4. argocd-secrets: now with the webhook and the CRDs available. This
#    sync is ALSO KSOPS' functional gate (the first real decryption):
argo_sync argocd-secrets

# argo_secrets_gate (run #4): it tells a BROKEN kustomize build
# (ComparisonError — temporal coupling) from timing, and demands a
# real Synced (Healthy is trivial for Apps made of Secrets):
argo_secrets_gate argocd-secrets
# the sync is asynchronous with respect to the resource apply — poll,
# not an instantaneous check (run #4, bug 6):
gate "ksops-funcional" poll 180 5 bash -c \
  "kubectl -n argocd get secret github-webhook >/dev/null 2>&1"
gate "generator-completo" poll 180 5 bash -c \
  "kubectl -n argocd get secret hello-aegis-repo ops-stack-repo >/dev/null 2>&1"
# (A7: post-sync validation ALWAYS — Synced+Healthy does not guarantee
#  the Secrets if a generator entry is missing)

# 5. argocd self-adoption (an App without automated — ADR-0012).
#    Runs #7/#8: it came out Synced/Healthy — the OutOfSync of #5 was
#    transient git, not drift (risk #2 CLOSED positive). The canonical
#    argo_sync already waits for the operation's TERMINAL phase (bug C
#    #8: the health-vs-operationState race on re-runs lived HERE). ONE
#    retry is kept for transient git (the operator's network — "failed
#    to get git client", seen in #5/#8):
if ! argo_sync argocd 600; then
    log_warn "the self App's sync failed (transient git?) — retrying once"
    argo_sync argocd 600 || \
        die "the self App's sync failed twice — check the repo-server/network and --from 35"
fi
if ! kubectl -n argocd get application argocd \
       -o jsonpath='{.status.sync.status}' | grep -qx Synced; then
    log_warn "App argocd OutOfSync after a successful sync — an adoption leftover (benign: Healthy + no automated); resources:"
    kubectl -n argocd get application argocd -o jsonpath=\
'{range .status.resources[?(@.status=="OutOfSync")]}{.kind}/{.name}{"\n"}{end}' >&2 || true
fi
gate "argocd-self-healthy" bash -c \
  "kubectl -n argocd get application argocd \
     -o jsonpath='{.status.health.status}' | grep -qx Healthy"

# 6. what was left of the base plane (cert-manager, the PKI and
#    traefik were already synced ABOVE, before argocd-secrets — the
#    fix for Finding A v1.1; re-syncing them here would be redundant):
argo_sync cloudflare-tunnel         # cloudflared (phase 25's token)

# ── end-to-end edge gates ──────────────────────────────────────────
gate "cloudflared-conectado" bash -c \
  "kubectl -n infra-edge rollout status deploy/cloudflared --timeout=180s >/dev/null"
# public DNS + tunnel + traefik answering (a 404 from traefik = OK,
# there are no app IngressRoutes yet). P1.13 audit: retry_net 6 gave
# ~30s to the PUBLIC DNS PROPAGATION of a freshly created CNAME — it
# normally takes minutes. poll 600 10 with a bounded curl.
#
# #87 (2026-08-13): this gate accepted `30[12]`, and since Access sits
# in front of argocd.<dom> (#76) a 302 is EXACTLY what Cloudflare's
# edge returns when it does NOT let you through. That is: the gate
# called "edge-responde" passed without the request entering the
# tunnel, without touching traefik and without seeing argocd-server.
# Green with the whole cluster switched off.
#
# edge_origin_responds traverses Access with the service token phase
# 25 left in the store, and separates the three outcomes that used to
# be one: the origin answered / Access intercepted / there was no
# answer. The codes are still 200 or 404 (traefik with no IngressRoute
# yet) — but now they come FROM THE ORIGIN.
#
# The gate is written with line continuations (\) and the diagnostic
# on ONE line on purpose: check 67 of verify-static joins the
# continuations and demands seeing `poll` on the same logical line as
# "edge-responde". A real newline inside the string breaks it.
DIAG35='kubectl -n infra-edge get pods 2>/dev/null | tail -n 3; kubectl -n infra-edge logs deploy/cloudflared --tail=15 2>/dev/null'
gate_diag "edge-responde" "$DIAG35" \
  poll 600 10 edge_origin_responds "https://argocd.$ROOT_DOMAIN" '^(200|404)$'

# a functional GitHub→ArgoCD webhook (the HMAC on BOTH sides is the
# same because phase 15 always RE-SYNCHRONIZES it — a PATCH over
# existing hooks, bug run #10: a surviving hook with an old HMAC gave
# a 400 here with a perfectly healthy edge). A real test: redeliver
# the last delivery and wait for a 2xx on GitHub's side. The hook is
# resolved by its URL (argocd-server listens on plain HTTP behind the
# edge; the public URL is https):
WEBHOOK_URL="https://argocd.$ROOT_DOMAIN/api/webhook"
# retry_net: with errexit ALIVE (F-A #15) a blink from gh here would
# kill the phase — it used to fall mute into a gate 2 lines later:
HOOK_ID="$(retry_net 3 gh api "repos/$GH_OWNER/$PLATFORM_REPO/hooks" \
    --jq ".[] | select(.config.url==\"$WEBHOOK_URL\") | .id")"
gate "hook-argocd-registrado" test -n "$HOOK_ID"
DELIVERY_ID="$(retry_net 3 gh api \
    "repos/$GH_OWNER/$PLATFORM_REPO/hooks/$HOOK_ID/deliveries" \
    --jq '.[0].id')"
gate "hook-tiene-deliveries" test -n "$DELIVERY_ID"
run_cmd gh api -X POST \
    "repos/$GH_OWNER/$PLATFORM_REPO/hooks/$HOOK_ID/deliveries/$DELIVERY_ID/attempts"
# the redeliver is asynchronous; the most recent delivery must end 2xx:
gate "webhook-redeliver-2xx" poll 180 5 bash -c \
    "gh api 'repos/$GH_OWNER/$PLATFORM_REPO/hooks/$HOOK_ID/deliveries' \
       --jq '.[0].status_code' | grep -q '^2'"

log_ok "GitOps operational: root + base plane Healthy, edge answering"
