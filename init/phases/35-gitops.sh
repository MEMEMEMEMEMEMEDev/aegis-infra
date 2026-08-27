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
# ── D5, the other half: on a RE-INIT the signature policy goes OFF ──
# The seed lists no ClusterPolicy (resources: []) and phase 80 is the
# last thing that turns it on — with the CA and the regcred already in
# Kyverno. A platform/ that came from a PREVIOUS cluster (destroy +
# init on the same host) already lists it: root would sync it in this
# phase, Enforce would be live on a Kyverno that cannot reach the
# registry yet, and phase 70's canary would be blocked on every image
# (second init of the rehearsal, 2026-08-27). So what phase 80 turns
# on, this phase turns OFF first; 80 turns it on again, in order.
KPK35="$PLATFORM_DIR/k8s/base/kyverno-policies/kustomization.yaml"
if yaml_lists_file "$KPK35" clusterpolicy-require-aegis-signature.yaml; then
    log_warn "kyverno-policies already lists the signature policy — a platform/ from a previous cluster; Enforce goes OFF until phase 80 re-arms it"
    run_cmd python3 - "$KPK35" <<'EOF'
import sys
p = sys.argv[1]
t = open(p).read().replace(
    "resources:\n  - clusterpolicy-require-aegis-signature.yaml",
    "resources: []")
open(p, "w").write(t)
EOF
    git_commit_if_changes "$PLATFORM_DIR" \
        "chore(kyverno): Enforce off until phase 80 re-arms it (re-init over a previous instance)"
    git_push_verified "$PLATFORM_DIR"
fi
gate "politica-apagada-hasta-80" bash -c \
  "python3 -c \"import yaml,sys; r=(yaml.safe_load(open('$KPK35')) or {}).get('resources') or []; sys.exit(1 if any('clusterpolicy' in x for x in r) else 0)\""

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

# ── 6. THE EDGE — AND HERE THE TWO PROFILES PART WAYS ──────────────
# Everything above this line is the same platform under both edges:
# ArgoCD, the internal PKI and traefik do not know how traffic reaches
# them. What follows DOES know, because it IS the edge and the
# measurement of the edge.
#
# EDGE=cloudflare: the edge is a pod that dials OUT (cloudflared, with
# the token phase 25 minted) plus a public name in a zone. The
# platform is measured from OUTSIDE, crossing Access with a service
# token.
#
# EDGE=local: there is no pod, no zone, no Access and no account ids.
# The edge is the systemd bridge on the HOST (share/systemd, installed
# by phase 25), which hands $EDGE_BIND_IP:80/443 to traefik's FIXED
# ClusterIP 10.43.0.80. What that profile loses is the PUBLIC path:
# nobody outside this machine reaches the platform, GitHub's senders
# included — that is the whole cost, stated once here and paid twice
# below. What it does NOT lose is the measurement: bridge → traefik →
# IngressRoute → argocd-server are the same four links a browser on
# this host crosses, and by this point in the phase all four exist
# (the bridge since phase 25, traefik and the route a few lines up).
if [[ "${EDGE:-cloudflare}" == local ]]; then
    # The wildcard *.$ROOT_DOMAIN of the internal CA — which traefik
    # serves on 443 through the default TLSStore — is ON the path
    # about to be measured. Under cloudflare that App is inert (the
    # tunnel delivers plain HTTP on `web`) and root's auto-sync brings
    # it up whenever it gets round to it; here the phase WAITS for it
    # instead of racing it, or the probe below meets traefik's
    # self-signed placeholder and blames the edge for a certificate.
    argo_sync edge-tls 300

    # cloudflared: NO SUBJECT. With no zone there is nothing to dial
    # out to and phase 25 minted no tunnel token, so this phase does
    # not sync the App and the rollout gate has nothing to look at.
    # RECORDED as skipped in the EV-08 idiom (phase 80): a gate that
    # vanishes in silence reads, months later, exactly like a gate
    # that passed.
    _gate_record "cloudflared-conectado" not-evaluated 0
    log_warn "GATE cloudflared-conectado has NO SUBJECT (recorded, not silent) — EDGE=local: there is no zone and no tunnel, so cloudflared is not deployed and this phase does not sync the cloudflare-tunnel App. What goes with it is the public path: the platform answers at EDGE_BIND_IP and nowhere else"

    # The chain is validated against the internal CA read FROM the
    # cluster, because there is nowhere else on this host to read it
    # from. Phase 40's role writes aegis-ca.pem into
    # /etc/rancher/k3s/ for CONTAINERD (the registry mirror) and does
    # NOT add it to the OS trust store — and phase 40 runs after this
    # one anyway. A curl from here trusts nothing that aegis signed
    # unless it is told where to look, and a probe that did not know
    # that would report a perfectly healthy edge as dead.
    #
    # curl takes it from CURL_CA_BUNDLE, so the probe still goes
    # through edge_origin_responds instead of a curl of its own: check
    # 90 exists precisely so that no branch curls this hostname by
    # hand, and the helper's three outcomes are worth just as much
    # here — with no service token in the store it goes direct and
    # says so, and the "no transport" case is exactly what a bridge
    # that is not listening looks like.
    #
    # Not `-k`: verifying the chain IS half of what the local edge
    # promises. `-k` would prove that something answers on 443, not
    # that traefik serves the certificate this instance issued.
    EDGE_CA="$(mktemp /dev/shm/aegis-edge-ca.XXXXXX)"
    # a CA certificate is public material, but a probe should not leave
    # litter in tmpfs when its gate dies:
    trap 'rm -f "$EDGE_CA"' EXIT
    # No `|| true` here, and check 009 is right to demand it: swallowing
    # the error of the command that fetches the CA is how a probe ends up
    # measuring against an EMPTY bundle and calling the result green. The
    # failure is captured, and the branch below decides what it means.
    if ! kubectl -n cert-manager get secret aegis-internal-ca \
        -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d > "$EDGE_CA" 2>/dev/null; then
        log_warn "the internal CA could not be read from the cluster — the edge probe below will say it could NOT be evaluated, and will not pretend otherwise"
    fi
    if [[ -s "$EDGE_CA" ]]; then
        export CURL_CA_BUNDLE="$EDGE_CA"
        # The evidence of a local edge is not cloudflared's log: it is
        # the three places it can break — the name not resolving to
        # the bind IP, the host bridge not listening (or pointing at a
        # ClusterIP from a previous cluster, which is what
        # /etc/aegis/edge.env is for), and traefik or the wildcard not
        # being up. Written with continuations and the diagnosis on
        # ONE line, for the same reason as the cloudflare branch
        # (check 67 joins the continuations).
        DIAG35L='getent hosts "argocd.$ROOT_DOMAIN" || echo "argocd.$ROOT_DOMAIN does not resolve"; systemctl --no-pager is-active aegis-edge-http.socket aegis-edge-https.socket 2>/dev/null; cat /etc/aegis/edge.env 2>/dev/null; ss -lnt 2>/dev/null | grep -E ":(80|443) " ; kubectl -n infra-edge get svc traefik 2>/dev/null; kubectl -n infra-edge get certificate aegis-edge-wildcard 2>/dev/null; kubectl -n infra-edge get pods 2>/dev/null | tail -n 3'
        # poll, not a single shot: what is being waited for is not a
        # public DNS propagation (there is none — sslip.io answers the
        # bind IP from the first second) but traefik loading the route
        # and the wildcard. Minutes, not tens of minutes.
        gate_diag "edge-responde" "$DIAG35L" \
          poll 300 10 edge_origin_responds "https://argocd.$ROOT_DOMAIN" '^(200|404)$'
        unset CURL_CA_BUNDLE
        EDGE_VERDICT="local edge answering at $EDGE_BIND_IP"
    else
        # THE THIRD OUTCOME. Not a pass and not a failure: with no CA
        # material an https probe cannot tell «the edge is down» from
        # «the chain cannot be validated», and answering that question
        # wrong sends the operator to the wrong half of the system.
        _gate_record "edge-responde" not-evaluated 0
        log_warn "GATE edge-responde COULD NOT BE EVALUATED (recorded, not silent) — the ca.crt of the aegis-internal-ca Secret (namespace cert-manager) could not be read, so there is no way to validate the chain the local edge serves. NOT measured: this is a WARNING, not an approval — the edge may be answering or may be dead, and nobody looked"
        EDGE_VERDICT="local edge NOT MEASURED (see the warning above)"
    fi
    rm -f "$EDGE_CA"; trap - EXIT

    # ── the GitHub→ArgoCD webhook: NO SUBJECT ──────────────────────
    # The hook exists because the tunnel publishes argocd.<domain> and
    # GitHub can POST to it. Under EDGE=local that hostname resolves
    # (sslip.io does its job) to EDGE_BIND_IP — an address of THIS
    # host — and there is nothing underneath publishing it, so
    # GitHub's senders have nowhere to deliver. Phase 15 registers no
    # hook on this edge, and the three gates lose their subject at
    # once: no hook to look up, no delivery to read, no 2xx to demand.
    #
    # What is lost is the PROMPTNESS, not the sync: ArgoCD keeps
    # reconciling the repository on its own timer (~3m by default), so
    # a push still lands — later, and because ArgoCD went to look, not
    # because GitHub knocked. And one link stops being measured: the
    # HMAC. The github-webhook Secret is still deployed and its
    # decryption IS measured above (ksops-funcional) — what nothing
    # exercises on this edge is the receiver validating a signature.
    _gate_record "hook-argocd-registrado" not-evaluated 0
    _gate_record "hook-tiene-deliveries" not-evaluated 0
    _gate_record "webhook-redeliver-2xx" not-evaluated 0
    log_warn "GATES hook-argocd-registrado, hook-tiene-deliveries and webhook-redeliver-2xx have NO SUBJECT (recorded, not silent) — EDGE=local: GitHub cannot deliver to argocd.$ROOT_DOMAIN, which resolves to EDGE_BIND_IP, an address of this host with no tunnel publishing it. There is no hook, no delivery and no HMAC exercised: a push reaches the cluster through ArgoCD's own reconciliation, minutes later"
else
    # what was left of the base plane: cert-manager, the PKI and
    # traefik were already synced ABOVE, before argocd-secrets — the
    # fix for Finding A v1.1; re-syncing them here would be redundant.
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

    EDGE_VERDICT="edge answering"
fi

log_ok "GitOps operational: root + base plane Healthy, $EDGE_VERDICT"
