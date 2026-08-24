#!/usr/bin/env bash
# PHASE 15 — third-party credentials, AUTOMATIC (D11).
#
# PHILOSOPHY (redesign after run #2): manual friction is NOT security.
# ZERO browser, ZERO files for the operator to move around, ZERO
# tokens created by hand in dashboards. What this phase asks of the
# human: paste ONE Cloudflare master credential (ephemeral: it is used
# to mint the scoped tokens and then destroyed from tmpfs). Everything
# else — deploy keys, webhooks, CI credential, scoped tokens — the
# init does over API/CLI.
#
# The GitHub App was REPLACED (D11): creating one without a browser
# does not exist (the manifest flow requires a web redirect) and
# minting PATs over the API does not either — the CI credential is the
# gh session's token (`gh auth token`), with its trade-off documented
# in docs/protocols/github-credential.md.
#
# Idempotence (bug 6): every generated secret goes to the encrypted
# store (gen_or_restore) — a --from here REUSES, it does not
# regenerate.
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
secrets_workdir

TOKENS_DIR="$PLATFORM_DIR/tofu/secrets"
B="$PLATFORM_DIR/k8s/base"

# ═══ 15.1 Cloudflare: ONE ephemeral master → scoped tokens ════════
# The operator does NOT create tokens in the dash. They paste their
# master credential (Global API Key, or an account token with "Account
# API Tokens: Edit"); the init mints the 2 scoped ones via the
# account-owned tokens API and shreds the master.
# The scoped ones are persisted encrypted (a re-run asks for nothing).
_cf_call() {   # _cf_call <method> <path> [json-payload-file]
    local method="$1" path="$2" payload="${3:-}"
    # W-03/SEC-12: the CF master does NOT travel through argv
    # (/proc/PID/cmdline). The header carrying the secret goes into a
    # curl config in tmpfs (600) via -K, just like the netrc-in-a-file
    # of jenkins.sh. X-Auth-Email is not a secret and may stay in argv.
    local cfg="$SECRETS_TMP/cf.curlcfg"
    ( umask 077
      if [[ "$CF_AUTH_MODE" == "key" ]]; then
          printf 'header = "X-Auth-Key: %s"\n' "$(cat "$CF_MASTER")" > "$cfg"
      else
          printf 'header = "Authorization: Bearer %s"\n' "$(cat "$CF_MASTER")" > "$cfg"
      fi )
    local args=(-sS -K "$cfg" -X "$method" \
                "https://api.cloudflare.com/client/v4$path" \
                -H "Content-Type: application/json")
    [[ "$CF_AUTH_MODE" == "key" ]] && args+=(-H "X-Auth-Email: $CF_AUTH_EMAIL")
    [[ -n "$payload" ]] && args+=(--data "@$payload")
    curl "${args[@]}"
}

CF_API_FILE="$STATE_SECRETS/cf_api_token.enc"
CF_DNS_FILE="$STATE_SECRETS/cf_dns_token.enc"
# #88 (2026-08-13): the THIRD scoped token. Access was applied by hand
# in #76 because this phase did not know how to mint it, and that
# meant a new instance was born with argocd and jenkins on the open
# internet — exactly the state #76 came to close, reappearing in every
# future installation. Fixing one instance is worth nothing if the
# init gives birth to it broken again.
#
# It sits under the SAME condition as the other two on purpose: if ONE
# is missing, the master has to be asked for anyway, so the three are
# minted together or not at all. An instance with 2 of 3 asking for
# the master is correct, not an edge case.
CF_ACCESS_FILE="$STATE_SECRETS/cf_access_token.enc"
if [[ -f "$CF_API_FILE" && -f "$CF_DNS_FILE" && -f "$CF_ACCESS_FILE" ]]; then
    log_info "scoped CF tokens already in the store — not asking for the master (re-run)"
    CF_API="$(restore_secret cf_api_token)"
    CF_DNS="$(restore_secret cf_dns_token)"
    CF_ACCESS="$(restore_secret cf_access_token)"
else
    # P0.3 audit 2026-07-18 — the FILE path (unattended, or the
    # operator's preference): CF_MASTER_FILE points at the master
    # (ideally in the launcher's /dev/shm). It is COPIED to our tmpfs
    # and we warn to destroy the origin; the prompt stays as a
    # fallback:
    if [[ -n "${CF_MASTER_FILE:-}" ]]; then
        [[ -s "$CF_MASTER_FILE" ]] || \
            die "CF_MASTER_FILE points at '$CF_MASTER_FILE' and it is empty/does not exist"
        install -m 600 "$CF_MASTER_FILE" "$SECRETS_TMP/cf_master"
        CF_MASTER="$SECRETS_TMP/cf_master"
        log_warn "CF master read from CF_MASTER_FILE — destroy the source file (shred -u) as soon as this phase ends"
    elif ni_mode; then
        die "--non-interactive without CF_MASTER_FILE — the CF master credential cannot be asked for at a prompt with no operator"
    else
        printf '\nCloudflare: the init is going to MINT the 2 scoped tokens\n' >&2
        printf 'over the API. It needs ONE master credential, ephemeral (it\n' >&2
        printf 'lives only in memory during this step):\n' >&2
        printf '  - your Global API Key (37 hex), or\n' >&2
        printf '  - an ACCOUNT API token with the permission\n' >&2
        printf '    "Account API Tokens: Edit".\n' >&2
        CF_MASTER="$(prompt_secret_manual 'CF master credential' 30 cf_master)"
    fi
    if [[ "$(cat "$CF_MASTER")" =~ ^[0-9a-f]{37}$ ]]; then
        CF_AUTH_MODE=key
        if ni_mode; then
            CF_AUTH_EMAIL="$ACME_EMAIL"
        else
            read -rp "email of the CF account [${ACME_EMAIL}]: " CF_AUTH_EMAIL \
                || die "stdin closed while asking for the CF account email"
            CF_AUTH_EMAIL="${CF_AUTH_EMAIL:-$ACME_EMAIL}"
        fi
    else
        CF_AUTH_MODE=bearer CF_AUTH_EMAIL=""
    fi
    # permission groups BY NAME against the live API (not IDs from
    # memory — the source-is-the-binary rule). If a name does not
    # match, it fails LISTING what is available (evidence, not
    # guesswork). ENDPOINT /accounts/, NOT /user/ (bug 1 validation
    # #3): /user/ demands "user-level authentication" (error 9109) and
    # only the Global API Key has it; with an account token —the
    # natural thing to create— it fails. /accounts/ works with BOTH
    # credentials:
    _cf_call GET "/accounts/$CF_ACCOUNT_ID/tokens/permission_groups" \
        > "$SECRETS_TMP/cf_pgroups.json"
    gate "cf-permission-groups" bash -c \
        "jq -e '.success == true' '$SECRETS_TMP/cf_pgroups.json' >/dev/null"
    mint_cf_token() {   # <store-name> <token-name> <python-policy-builder>
        local store="$1" tok_name="$2" builder="$3"
        python3 "$builder" "$SECRETS_TMP/cf_pgroups.json" "$tok_name" \
            "$CF_ACCOUNT_ID" "$CF_ZONE_ID" > "$SECRETS_TMP/mint.json" || \
            die "the permission groups did not match — check the names above"
        _cf_call POST "/accounts/$CF_ACCOUNT_ID/tokens" \
            "$SECRETS_TMP/mint.json" > "$SECRETS_TMP/mint_res.json"
        jq -e '.success == true' "$SECRETS_TMP/mint_res.json" >/dev/null || \
            die "CF rejected the creation of token $tok_name: $(jq -c '.errors' "$SECRETS_TMP/mint_res.json")"
        jq -r '.result.value' "$SECRETS_TMP/mint_res.json" | tr -d '\n' \
            > "$SECRETS_TMP/$store"
        persist_secret "$store" "$SECRETS_TMP/$store"
        log_ok "scoped CF token minted: $tok_name"
        printf '%s' "$SECRETS_TMP/$store"
    }
    CF_API="$(mint_cf_token cf_api_token aegis-v2-tunnel \
              "$AEGIS_ROOT/lib/cf-policy-tunnel.py")"
    CF_DNS="$(mint_cf_token cf_dns_token aegis-v2-dns-cert-manager \
              "$AEGIS_ROOT/lib/cf-policy-dns.py")"
    # #88: the Access one. SEPARATE from the one above and not just
    # one more permission on it, because Jenkins' edge-apply job
    # receives the tunnel's token: if that token could edit Access, a
    # compromised CI could take itself out from behind Access.
    CF_ACCESS="$(mint_cf_token cf_access_token aegis-v2-access \
                 "$AEGIS_ROOT/lib/cf-policy-access.py")"
    # the master dies HERE (ephemeral for real):
    shred -u "$CF_MASTER"
    unset CF_AUTH_EMAIL
    log_ok "CF master destroyed from tmpfs; ONLY the scoped ones remain"
fi

# ═══ 15.2 Our own material (HMACs, deploy keys) — from the store ══
HMAC_ARGO="$(gen_or_restore hmac_argocd gen_hex32)"
HMAC_JENK="$(gen_or_restore hmac_jenkins gen_hex32)"
# run #12: the HMACs live in TWO places that must be byte-identical
# (a byte-preserving K8s Secret vs GitHub, which trims) — a trailing
# \n = a deterministic 400 on every delivery. It is validated here
# because the store RESTORES old material verbatim (pre-fix):
assert_no_newline "$HMAC_ARGO" hmac_argocd
assert_no_newline "$HMAC_JENK" hmac_jenkins

# ONE KEY PER CONSUMER, and ALL of them read-only (#83, 2026-08-12).
#
# Until now there was a WRITE key (dk_app_rw, registered as
# `aegis-iu-write --allow-write`) that existed for the Image Updater,
# and ArgoCD authenticated with IT. The Image Updater was retired in
# #59 and the key was removed from GitHub by hand in #49 — but this
# phase kept creating and registering it, so every new instance was
# born with it again. Measured on 2026-08-12: it was gone from GitHub,
# still there in the init.
#
# The direction mattered: ArgoCD only READS. A deploy key with write
# access in its Secret means whoever holds the cluster can write to
# the app's repo — the opposite of what you want.
#
# And they are SEPARATE keys per consumer on purpose: with a shared
# one, rotating Jenkins' key forces you to touch ArgoCD, and the blast
# radius of each rotation stops being the consumer and becomes
# everyone.
DK_OPS="$(gen_or_restore_keypair dk_ops "argocd-readonly@${PLATFORM_REPO}")"
DK_APP_RO="$(gen_or_restore_keypair dk_app_ro "jenkins-readonly@${APP_REPO}")"
DK_APP_ARGO="$(gen_or_restore_keypair dk_app_argocd_ro "argocd-readonly@${APP_REPO}")"

# ═══ 15.3 AUTOMATIC deploy key registration (gh, idempotent) ══════
# before: a human_step with 3 pastes into the UI. Now: gh repo
# deploy-key add (tested by the operator on run #2).
# Idempotence by title: if it is already registered, skip.
add_deploy_key() {   # <repo> <pubfile> <title> [--allow-write]
    local repo="$1" pub="$2" title="$3" write="${4:-}"
    # idempotence by FINGERPRINT, not by title (run #7): if the repo
    # survived a previous run (greenfield-vs-state: the snapshot wipes
    # the VM, not GitHub) its registered deploy key holds the OLD
    # public key, but the store regenerated the private one → they do
    # not match → "Permission denied (publickey)". The skip-by-title
    # did NOT detect it. We compare the key's base64 blob:
    local ourkey existing
    ourkey="$(awk '{print $2}' "$pub")"
    existing="$(gh repo deploy-key list -R "$GH_OWNER/$repo" \
                  --json title,key --jq \
                  ".[] | select(.title==\"$title\") | .key" 2>/dev/null \
                | awk '{print $2}')"
    if [[ -n "$existing" ]]; then
        if [[ "$existing" == "$ourkey" ]]; then
            log_info "deploy key '$title' already registered and it MATCHES the store — skip"
            return 0
        fi
        log_warn "the registered deploy key '$title' does NOT match the store (repo from a previous run) — re-registering"
        local oldid
        oldid="$(gh repo deploy-key list -R "$GH_OWNER/$repo" --json id,title \
                  --jq ".[] | select(.title==\"$title\") | .id")"
        run_cmd gh repo deploy-key delete -R "$GH_OWNER/$repo" "$oldid"
    fi
    local args=(-R "$GH_OWNER/$repo" --title "$title")
    [[ "$write" == "--allow-write" ]] && args+=(--allow-write)
    run_cmd gh repo deploy-key add "$pub" "${args[@]}"
    log_ok "deploy key '$title' registered in $repo${write:+ (WRITE)}"
}
add_deploy_key "$PLATFORM_REPO" "$DK_OPS.pub"      aegis-argocd-ro
add_deploy_key "$APP_REPO"      "$DK_APP_RO.pub"   aegis-jenkins-ro
add_deploy_key "$APP_REPO"      "$DK_APP_ARGO.pub" aegis-argocd-ro

# real verification of the registration (real capability, not a
# proxy). One per key: a gate covering two consumers does not say
# which one broke.
gate "deploy-key-ops-lee" retry_net 3 bash -c \
  "GIT_SSH_COMMAND='ssh -i $DK_OPS -o IdentitiesOnly=yes' \
   git ls-remote git@github.com:$GH_OWNER/$PLATFORM_REPO.git HEAD >/dev/null"
gate "deploy-key-app-jenkins-lee" retry_net 3 bash -c \
  "GIT_SSH_COMMAND='ssh -i $DK_APP_RO -o IdentitiesOnly=yes' \
   git ls-remote git@github.com:$GH_OWNER/$APP_REPO.git HEAD >/dev/null"
gate "deploy-key-app-argocd-lee" retry_net 3 bash -c \
  "GIT_SSH_COMMAND='ssh -i $DK_APP_ARGO -o IdentitiesOnly=yes' \
   git ls-remote git@github.com:$GH_OWNER/$APP_REPO.git HEAD >/dev/null"

# ═══ 15.4 AUTOMATIC webhooks (gh api --input, secret out of argv) ═
make_repo_webhook() {   # <repo> <url> <hmac-file>
    local repo="$1" url="$2" hmac="$3" hook_id
    # bug run #10: "it already exists" does NOT imply "it is in sync".
    # A hook surviving from a previous state signs with an old HMAC
    # while the receiver validates with the store's one
    # (gen_or_restore) → a permanent 400 on the redeliver. Unlike the
    # deploy key above (whose public blob CAN be compared), GitHub
    # NEVER returns config.secret of an existing hook — no comparison
    # is possible. The only guarantee of being in sync: ALWAYS
    # re-write the secret (an idempotent PATCH with the store's HMAC).
    # P3 audit: listing with `2>/dev/null | head` treated a network
    # failure as "there is no hook" → a duplicate POST on every
    # half-finished resume. retry + EXPLICIT failure of the listing:
    local hooks_json
    hooks_json="$(retry_net 3 gh api "repos/$GH_OWNER/$repo/hooks")" || \
        die "could not LIST the hooks of $repo (network/gh) — without a listing you cannot tell creating from duplicating"
    hook_id="$(jq -r ".[] | select(.config.url==\"$url\") | .id" \
               <<< "$hooks_json" | head -n1)"
    python3 - "$url" "$hmac" "${hook_id:+patch}" \
        > "$SECRETS_TMP/hook.json" <<'EOF'
import json, sys
url, hmac_file = sys.argv[1], sys.argv[2]
body = {"active": True, "events": ["push"],
        "config": {"url": url, "content_type": "json",
                   "secret": open(hmac_file).read().strip(),
                   "insecure_ssl": "0"}}
if len(sys.argv) < 4 or sys.argv[3] != "patch":
    body["name"] = "web"   # POST demands it; PATCH does not accept it
print(json.dumps(body))
EOF
    if [[ -n "$hook_id" ]]; then
        run_cmd bash -c "gh api -X PATCH 'repos/$GH_OWNER/$repo/hooks/$hook_id' \
            --input '$SECRETS_TMP/hook.json' >/dev/null"
        log_ok "webhook $url already existed in $repo — HMAC re-synchronized with the store (PATCH, never in argv)"
        return 0
    fi
    run_cmd bash -c "gh api -X POST 'repos/$GH_OWNER/$repo/hooks' \
        --input '$SECRETS_TMP/hook.json' >/dev/null"
    log_ok "webhook created in $repo → $url (HMAC never in argv)"
}
# GitHub accepts URLs that are still unreachable (the edge arrives in
# phase 35; the redeliver/e2e gates close the loop afterwards):
make_repo_webhook "$PLATFORM_REPO" "https://argocd.$ROOT_DOMAIN/api/webhook" "$HMAC_ARGO"
make_repo_webhook "$APP_REPO"      "https://jenkins.$ROOT_DOMAIN/github-webhook/" "$HMAC_JENK"

# ═══ 15.5 CI credential for Jenkins (D11: gh token, not an App) ═══
# github-branch-source scans with a username+password credential
# (owner + token) — the standard pre-App path. The token is the gh
# session's one (dogfooding; trade-off and rotation in
# docs/protocols/github-credential.md). The mechanics without showing
# it:
gh auth token | tr -d '\n' > "$SECRETS_TMP/gh_token"
gate "gh-token-no-vacio" bash -c "[[ -s '$SECRETS_TMP/gh_token' ]]"
# P2.5 audit 2026-07-18: the session token is baked in as the CI
# credential — if it lacks the repo scope, the multibranch scan fails
# DAYS later with no correlation to this phase. A gate on the REAL
# scopes (the API's x-oauth-scopes header, not gh's docs):
gate "gh-token-scope-repo" retry_net 3 bash -c \
  "gh api -i user 2>/dev/null | grep -i '^x-oauth-scopes:' | grep -qw repo"
# (token rotation/expiry: docs/protocols/github-credential.md)
GH_USER_F="$(materialize gh_user "$GH_OWNER")"

# ═══ 15.6 Encryption of everything produced (KSOPS + tofu) ════════
# tokens.enc.yaml = ONLY the keys the tofu wrapper injects (D7/D10).
#
# #88: there are TWO of them since Access. tofu-apply.sh reads
# cloudflare.api_token and cloudflare.access_token, and dies with
# "empty" if either is missing — until today the second one had been
# put there by a hand in #76, so a new instance reached phase 25 and
# the edge apply stopped right there. Both come from the same place
# and by the same mechanism.
#
# That both live in the SAME file does not undo the separation: what
# holds the separation up is that CI never has the age key, so it
# cannot open this file. Jenkins' edge-apply job receives its token as
# a Jenkins credential, and it receives ONLY the tunnel's one.
python3 - "$CF_API" "$CF_ACCESS" > "$SECRETS_TMP/tokens.yaml" <<'EOF'
import sys, yaml
api = open(sys.argv[1]).read().strip()
access = open(sys.argv[2]).read().strip()
yaml.safe_dump({"cloudflare": {"api_token": {"value": api},
                               "access_token": {"value": access}}},
               sys.stdout, default_flow_style=False)
EOF
# the destination has a versioned .gitkeep, but an `mv` into a
# nonexistent dir kills the phase dead (the bug of the run on native
# Linux, 2026-07-25: git does not version empty dirs and the VM was
# populated by copying, not by cloning). Defence in depth — cheap and
# with no effect if it already exists:
mkdir -p "$TOKENS_DIR"
mv "$SECRETS_TMP/tokens.yaml" "$TOKENS_DIR/tokens.enc.yaml"   # A5: mv first
sops_encrypt_repo "$TOKENS_DIR/tokens.enc.yaml"   # explicit --config (pattern A)
gate "tokens-roundtrip" check_sops_roundtrip "$TOKENS_DIR/tokens.enc.yaml"

# the dns token → a Secret the ClusterIssuers reference:
make_enc_secret cloudflare-dns-token cert-manager \
    "$B/ingress/cert-manager-issuers/secret-cloudflare-dns-token.enc.yaml" \
    "api-token=$CF_DNS"

# ── Jenkins credentials for the edge (#48) ────────────────────────
# ADDED on 2026-08-05. The four Secrets had existed in the repo since
# #45 but NO phase produced them: they had been created by hand with
# sops when the edge job was built, and were never wired up here.
#
# The failure mode is the one this project chases hardest: on a new
# instance the age key is a different one, the init re-encrypts
# everything it DOES produce, and these four stay encrypted with a key
# that no longer exists. KSOPS cannot decrypt them, the jenkins-secrets
# App never syncs, and the message talks about a MAC and about sops —
# not about a line that was missing here.
#
# All four values are already at hand in this phase: $CF_API is the
# very token that was just minted, and the other three come from the
# conf. There is nothing new to ask the operator for.
#
# Mind what each one is. The TOKEN is a credential —the edge job only
# READS the zone (§4 of docs/protocols/edge.md)— and the other three
# are identifiers, not secrets. They go encrypted all the same because
# the mechanism is a single one: an exception saying "this one does
# not need encrypting" is an exception you then have to remember.
CF_JENKINS_DESC="Cloudflare API token. Used by the edge-chequeo job (it only READS the zone) and by the operator via tofu-apply.sh. The age key does NOT enter CI."
make_enc_secret cloudflare-api-token jenkins-system \
    "$B/platform/jenkins-secrets/secret-cloudflare-api-token.enc.yaml" \
    --label jenkins.io/credentials-type=secretText \
    --annotation "jenkins.io/credentials-description=$CF_JENKINS_DESC" \
    "text=$CF_API"
make_enc_secret cloudflare-account-id jenkins-system \
    "$B/platform/jenkins-secrets/secret-cloudflare-account-id.enc.yaml" \
    --label jenkins.io/credentials-type=secretText \
    --annotation "jenkins.io/credentials-description=Cloudflare Account ID (an identifier, not a secret)." \
    "text=$(materialize cf_account_id "$CF_ACCOUNT_ID")"
make_enc_secret cloudflare-zone-id jenkins-system \
    "$B/platform/jenkins-secrets/secret-cloudflare-zone-id.enc.yaml" \
    --label jenkins.io/credentials-type=secretText \
    --annotation "jenkins.io/credentials-description=Cloudflare Zone ID (an identifier, not a secret)." \
    "text=$(materialize cf_zone_id "$CF_ZONE_ID")"
make_enc_secret root-domain jenkins-system \
    "$B/platform/jenkins-secrets/secret-root-domain.enc.yaml" \
    --label jenkins.io/credentials-type=secretText \
    --annotation "jenkins.io/credentials-description=The instance's root domain (an identifier, not a secret)." \
    "text=$(materialize root_domain "$ROOT_DOMAIN")"

make_enc_secret github-webhook argocd \
    "$B/platform/argocd-secrets/secret-github-webhook.enc.yaml" \
    --label app.kubernetes.io/part-of=argocd \
    "token=$HMAC_ARGO"

APP_URL="$(materialize app_repo_url "git@github.com:$GH_OWNER/$APP_REPO.git")"
APP_NAME="$(materialize app_repo_name "$APP_REPO")"
REPO_TYPE="$(materialize repo_type git)"
make_enc_secret hello-aegis-repo argocd \
    "$B/platform/argocd-secrets/secret-hello-aegis-repo.enc.yaml" \
    --label argocd.argoproj.io/secret-type=repository \
    "sshPrivateKey=$DK_APP_ARGO" \
    "url=$APP_URL" "name=$APP_NAME" "type=$REPO_TYPE"

GIT_USER="$(materialize git_user git)"
make_enc_secret hello-aegis-repo jenkins-system \
    "$B/platform/jenkins-secrets/secret-hello-aegis-repo.enc.yaml" \
    --label jenkins.io/credentials-type=basicSSHUserPrivateKey \
    --annotation "jenkins.io/credentials-description=RO deploy key, checkout ${APP_REPO}" \
    "privateKey=$DK_APP_RO" "username=$GIT_USER"

# checkout of the PLATFORM repo for the ci-images job (bug caught in
# session 6: the job cloned platform with the APP's key):
make_enc_secret ops-stack-repo-ro jenkins-system \
    "$B/platform/jenkins-secrets/secret-ops-stack-repo-ro.enc.yaml" \
    --label jenkins.io/credentials-type=basicSSHUserPrivateKey \
    --annotation "jenkins.io/credentials-description=RO deploy key, checkout ${PLATFORM_REPO} (ci-images job)" \
    "privateKey=$DK_OPS" "username=$GIT_USER"

# the CI credential (username+token — replaces the GitHub App):
make_enc_secret github-token jenkins-system \
    "$B/platform/jenkins-secrets/secret-github-token.enc.yaml" \
    --label jenkins.io/credentials-type=usernamePassword \
    --annotation "jenkins.io/credentials-description=gh session token for the multibranch scan (D11)" \
    "username=$GH_USER_F" "password=$SECRETS_TMP/gh_token"

make_enc_secret github-webhook-hmac jenkins-system \
    "$B/platform/jenkins-secrets/secret-github-webhook-hmac.enc.yaml" \
    --label jenkins.io/credentials-type=secretText \
    --annotation "jenkins.io/credentials-description=GitHub→Jenkins webhook HMAC" \
    "text=$HMAC_JENK"

OPS_URL="$(materialize ops_url "git@github.com:$GH_OWNER/$PLATFORM_REPO.git")"
OPS_NAME="$(materialize ops_name "$PLATFORM_REPO")"
make_enc_secret ops-stack-repo argocd \
    "$B/platform/argocd-secrets/secret-ops-stack-repo.enc.yaml" \
    --label argocd.argoproj.io/secret-type=repository \
    "sshPrivateKey=$DK_OPS" "url=$OPS_URL" \
    "name=$OPS_NAME" "type=$REPO_TYPE"

log_ok "AUTOMATIC third parties complete: CF tokens minted over the API, \
3 deploy keys registered via gh, 2 webhooks created, CI credential \
from the gh token — zero browser, zero files moved by hand"
