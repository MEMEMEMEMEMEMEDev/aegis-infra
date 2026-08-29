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
#
# THE EDGE (2026-08-26). Half of what this phase does is Cloudflare:
# three scoped tokens minted against an account, the file the tofu
# wrapper reads, the DNS token cert-manager would solve with, and the
# four values the edge job reads the zone with. With EDGE=local there
# is no account, no zone and no tunnel, so none of that has a subject
# — and each omitted step says so below, with the reason whole.
# What is NOT Cloudflare does NOT change in either profile: the two
# HMACs, the three deploy keys, their registration through gh and
# their three gates, and the CI credential out of the gh session. All
# of those hang off GitHub, and GitHub is there whichever way the
# platform is reached from outside.
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
# A conf written before 2026-08-26 carries no EDGE, and it could only
# have been cloudflare — the same reading config_validate does. It is
# spelled out here because with nounset alive a bare $EDGE would kill
# the phase on those confs instead of telling anyone why.
EDGE="${EDGE:-cloudflare}"
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
# EDGE=local: there is no Cloudflare account to mint anything against,
# so this whole step is left without a subject. The three tokens exist
# to drive a zone that does not exist here: the tunnel one (cloudflared
# and the DNS records, phase 25), the DNS one (the DNS-01 solver of the
# letsencrypt ClusterIssuers) and the Access one (the identity plane in
# front of argocd and jenkins, #88). With a local edge the platform is
# reached through the host bridge onto traefik's fixed ClusterIP and
# the TLS is issued by the instance's own internal CA.
#
# What is LOST, said whole and not as "skipped": these names are
# published nowhere outside this machine, no certificate is public, and
# there is NO Cloudflare Access in front of the operator apps — whoever
# reaches EDGE_BIND_IP reaches argocd's and jenkins' login screens with
# nothing but their own passwords in between. That is the trade of the
# local profile, and the reason its default bind is the loopback.
# ${EDGE:-cloudflare} and NOT "$EDGE": every phase runs in its own
# subshell (`( source "$p" )`), so the default config_validate applies
# does not survive phase 00. With a conf written before EDGE existed the
# variable is simply absent, and under `set -u` a bare "$EDGE" does not
# fall back to cloudflare — it kills the phase with «unbound variable».
# A conf with no EDGE is a cloudflare conf, which is the only thing it
# could ever have been.
if [[ "${EDGE:-cloudflare}" == local ]]; then
    log_info "EDGE=local: the 3 scoped Cloudflare tokens are NOT minted — there is no account to mint them against, and no zone, no tunnel and no Access for them to drive"
    log_warn "GATE cf-permission-groups has NO SUBJECT under EDGE=local: the permission groups are not read because no master credential is asked for. This is not the gate passing — it is the gate having nothing to look at"
    # The two Secrets these tokens feed are still WRITTEN below, empty:
    # their file names are listed in the seed's KSOPS generators, which
    # are identical in both profiles, and an entry with no producer
    # breaks the kustomize build of its App (A7) — cert-manager-issuers
    # and jenkins-secrets would never sync. An empty and annotated
    # Secret says "this profile has no Cloudflare"; a missing file says
    # nothing and takes two Apps down with it.
    CF_API="$(materialize cf_api_token_empty "")"
    CF_DNS="$(materialize cf_dns_token_empty "")"
    CF_ACCESS=""   # no consumer under local: tokens.enc.yaml is not written
    # And the fourth thing this phase mints since 2026-08-29: the pair
    # the backups leave the machine with. It hangs off the same account
    # as the three above, so with no account it has no subject either —
    # but its absence costs something different, and that difference is
    # the reason this says more than «skipped». The other three take
    # away hostnames, certificates and a login screen; this one takes
    # away the OFF-SITE COPY. An instance with a local edge captures its
    # bundles, encrypts them, verifies them, and leaves every one of
    # them on a disk of the same house — so a fire, a theft or a dead
    # controller takes the data and its backups together. It is a
    # legitimate profile and it is not a safe one, and the difference
    # has to be said where somebody reads it.
    log_warn "EDGE=local: the R2 credential is NOT minted — there is no Cloudflare account. The backups WILL be captured and encrypted, and they will stay on this machine: with this profile there is no off-site copy unless the operator wires their own transport (AEGIS_BACKUP_SINK, or an R2 account adopted by hand)"
    gate_no_subject "backup-r2-credential" \
      "EDGE=local: there is no account to mint an R2 token against, so nothing was measured about the off-site destination. It is NOT that the destination is fine — it is that this instance has none"
elif [[ -f "$CF_API_FILE" && -f "$CF_DNS_FILE" && -f "$CF_ACCESS_FILE" ]]; then
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
    # ── 15.1b THE OFF-SITE DESTINATION OF THE BACKUPS ───────────
    #
    # A backup that stays on the machine it has to survive is not a
    # backup, and until today every bundle this platform wrote stayed
    # there. The pair that gets it out is minted HERE, with the master
    # still alive, for the same reason the other three are: this is the
    # one moment in the whole life of the instance when there is a
    # credential able to create credentials.
    #
    # IT IS SCOPED TO ONE BUCKET, and that is the point of minting it
    # instead of asking for one. `Workers R2 Storage Bucket Item Write`
    # is a BUCKET-level permission group: the token can read, write and
    # list objects in the bucket the policy names, and nothing else in
    # the account. It cannot create buckets, cannot delete them, cannot
    # touch the zone. If the machine being backed up is compromised, what
    # the attacker holds is the ability to add and overwrite objects in
    # one shelf of ciphertext — not to erase the history, which is R2's
    # own lifecycle rule, and not to reach anything else.
    #
    # THE DERIVATION OF THE S3 PAIR IS MEASURED, NOT INVENTED. From
    # developers.cloudflare.com/r2/api/tokens, read on 2026-08-29:
    #   · Access Key ID     = the `id` of the API token.
    #   · Secret Access Key = the SHA-256 hash of the token's `value`.
    # Getting that wrong is the worst possible way to be wrong here: the
    # mint succeeds, the phase goes green, and the failure appears the
    # day somebody needs the copy. So the value never touches argv and
    # never touches a file — it goes from jq into sha256sum through a
    # pipe — and `remote adopt` LISTS the destination with the derived
    # pair before storing it. A credential that was not proved against
    # the thing it opens is a credential nobody proved.
    #
    # The policy is built inline and not in lib/cf-policy-*.py like the
    # other three. It is not a preference: those three shape a POLICY
    # over a zone with several permission groups each, and this one is a
    # single group over a single resource string. A file for four lines
    # of json would be a fourth place to look.
    #
    # THE BUCKET NAME IS ASKED FOR, not built. `aegis data remote bucket`
    # derives it from the root domain and is the same derivation the PUT
    # uses; if this phase built its own, a token scoped to one name and a
    # backup writing to another would both look correct.
    R2_BUCKET="$(${AEGIS_CMD:-aegis} data remote bucket)" \
        || die "the destination bucket could not be derived: without it the R2 token would be scoped to a name nobody writes to"
    python3 - "$SECRETS_TMP/cf_pgroups.json" "$CF_ACCOUNT_ID" "$R2_BUCKET" \
        > "$SECRETS_TMP/r2_mint.json" <<'EOF' || die "the R2 permission group did not match — check the names the API returned above"
import json, sys
groups = json.load(open(sys.argv[1]))["result"]
account, bucket = sys.argv[2], sys.argv[3]
# BY NAME against the live API, never an id from memory: the same rule
# as the other three tokens, and for the same reason (two documented
# cases of «the pin invented from memory did not exist»).
WANT = "Workers R2 Storage Bucket Item Write"
ids = [g["id"] for g in groups if g.get("name") == WANT]
if not ids:
    print(f"no permission group named {WANT!r}. Available: "
          f"{sorted(g.get('name', '') for g in groups)[:40]}", file=sys.stderr)
    sys.exit(1)
# The resource string, from the same page of the documentation:
# com.cloudflare.edge.r2.bucket.<ACCOUNT_ID>_<JURISDICTION>_<BUCKET>.
# `default` is the jurisdiction of a bucket created without one, which
# is what tofu/envs/data-r2 creates.
print(json.dumps({
    "name": "aegis-v2-backups-r2",
    "policies": [{
        "effect": "allow",
        "resources": {f"com.cloudflare.edge.r2.bucket.{account}_default_{bucket}": "*"},
        "permission_groups": [{"id": ids[0]}],
    }],
}))
EOF
    _cf_call POST "/accounts/$CF_ACCOUNT_ID/tokens" "$SECRETS_TMP/r2_mint.json" \
        > "$SECRETS_TMP/r2_res.json"
    gate "cf-r2-token-minted" bash -c \
      "jq -e '.success == true' '$SECRETS_TMP/r2_res.json' >/dev/null"
    # The two lines `remote adopt` reads. The token's VALUE never lands
    # anywhere: it goes from jq straight into sha256sum through a pipe,
    # so it is in no file and in no argv at any point.
    ( umask 077
      jq -r '.result.id' "$SECRETS_TMP/r2_res.json" | tr -d '\n' \
          > "$SECRETS_TMP/r2_credential"
      printf '\n' >> "$SECRETS_TMP/r2_credential"
      jq -r '.result.value' "$SECRETS_TMP/r2_res.json" | tr -d '\n' \
          | sha256sum | cut -d' ' -f1 >> "$SECRETS_TMP/r2_credential" )
    # And the response dies with the master: it carries the token's
    # value, which is the secret half before the hash.
    shred -u "$SECRETS_TMP/r2_res.json"
    # The store entry is written by the command that OWNS this material,
    # not by this phase: `remote adopt` is the one that knows how to
    # prove the pair against the destination before storing it, and
    # proving it is the difference between a credential and a hope.
    run_cmd ${AEGIS_CMD:-aegis} data remote adopt \
        --credentials-file "$SECRETS_TMP/r2_credential" \
        || die "the R2 pair was minted and the destination did NOT accept it — nothing was stored. A credential that does not open the bucket, sitting in the store, is an off-site copy that exists on paper"
    log_ok "off-site destination of the backups: scoped R2 token minted for the bucket $R2_BUCKET and adopted"

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
#
# The hooks are the one piece of this phase that is GitHub's on the
# outside and the edge's underneath: what they need is not a repo, it
# is a URL GitHub's delivery infrastructure can reach and trust. Under
# EDGE=local it cannot. The name resolves through sslip.io to
# EDGE_BIND_IP, which is the loopback by default; and even bound to a
# routable address the certificate is issued by the instance's internal
# CA, which GitHub does not trust — the hook is created with
# insecure_ssl "0", as it must be. A hook that can never deliver is not
# a hook: it is a red delivery on every push, forever, and a phase 60
# that gates on a link that was never going to close.
if [[ "${EDGE:-cloudflare}" == cloudflare ]]; then
    make_repo_webhook "$PLATFORM_REPO" "https://argocd.$ROOT_DOMAIN/api/webhook" "$HMAC_ARGO"
    make_repo_webhook "$APP_REPO"      "https://jenkins.$ROOT_DOMAIN/github-webhook/" "$HMAC_JENK"
else
    log_info "EDGE=local: the 2 GitHub webhooks are NOT created — GitHub would have to reach https://argocd.$ROOT_DOMAIN and https://jenkins.$ROOT_DOMAIN, which resolve to ${EDGE_BIND_IP:-the host bridge} and are served with a certificate from the instance's internal CA that GitHub does not trust"
    log_warn "EDGE=local: what is LOST is the INSTANT push, not the sync — ArgoCD keeps reconciling on its own polling interval and Jenkins keeps scanning its branches on its own schedule; a push simply takes as long as those cycles"
    # The two HMACs above are generated ALL THE SAME, on purpose: both
    # receivers load their Secret at boot (argocd/github-webhook and
    # jenkins-system/github-webhook-hmac, listed in the seed in both
    # profiles), and material that exists is material that does not
    # have to be invented the day this instance grows a real edge.
fi

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
#
# EDGE=local: nobody reads this file. Its only consumer is
# tofu/tofu-apply.sh, which exports the two tokens so that the tofu of
# the edge (tunnel, DNS records, Access apps) can apply — machinery
# that has no subject with no zone. Writing it with empty values would
# be worse than not writing it: tofu-apply.sh dies saying "empty", and
# that death would look like a broken instance instead of a profile
# that does not use tofu.
if [[ "${EDGE:-cloudflare}" == cloudflare ]]; then
    python3 - "$CF_API" "$CF_ACCESS" > "$SECRETS_TMP/tokens.yaml" <<'EOF'
import sys, yaml
api = open(sys.argv[1]).read().strip()
access = open(sys.argv[2]).read().strip()
yaml.safe_dump({"cloudflare": {"api_token": {"value": api},
                               "access_token": {"value": access}}},
               sys.stdout, default_flow_style=False)
EOF
    # the destination has a versioned .gitkeep, but an `mv` into a
    # nonexistent dir kills the phase dead (the bug of the run on
    # native Linux, 2026-07-25: git does not version empty dirs and the
    # VM was populated by copying, not by cloning). Defence in depth —
    # cheap and with no effect if it already exists:
    mkdir -p "$TOKENS_DIR"
    mv "$SECRETS_TMP/tokens.yaml" "$TOKENS_DIR/tokens.enc.yaml"   # A5: mv first
    sops_encrypt_repo "$TOKENS_DIR/tokens.enc.yaml"   # explicit --config (pattern A)
    gate "tokens-roundtrip" check_sops_roundtrip "$TOKENS_DIR/tokens.enc.yaml"
else
    log_info "EDGE=local: tokens.enc.yaml is NOT written — its only reader is the tofu wrapper of the edge, and with no Cloudflare zone there is no tofu of the edge to apply"
    gate_no_subject "tokens-roundtrip" \
      "EDGE=local: tokens.enc.yaml is never written, so there is no file to encrypt and no roundtrip to validate. Nothing was checked here — it is NOT that the encryption is fine"
fi

# the dns token → a Secret the ClusterIssuers reference:
#
# Under EDGE=local the Secret is written EMPTY and says why in an
# annotation. It cannot simply not be written: its name is listed in
# the KSOPS generator of cert-manager-issuers, the seed is identical in
# both profiles, and a listed file with no producer breaks that App's
# kustomize build (A7). Empty is honest here — the letsencrypt issuers
# solve DNS-01 against a zone that does not exist, and the wildcard
# this instance actually serves is issued by the internal CA.
if [[ "${EDGE:-cloudflare}" == cloudflare ]]; then
    make_enc_secret cloudflare-dns-token cert-manager \
        "$B/ingress/cert-manager-issuers/secret-cloudflare-dns-token.enc.yaml" \
        "api-token=$CF_DNS"
else
    make_enc_secret cloudflare-dns-token cert-manager \
        "$B/ingress/cert-manager-issuers/secret-cloudflare-dns-token.enc.yaml" \
        --annotation "aegis.dev/no-subject=EDGE=local: EMPTY on purpose. There is no Cloudflare account, so there is no DNS token: the letsencrypt ClusterIssuers cannot solve DNS-01 here and the TLS of this instance is issued by the aegis-internal-ca ClusterIssuer. The Secret exists because the KSOPS generator lists it in both profiles." \
        "api-token=$CF_DNS"
    log_warn "EDGE=local: Secret cert-manager/cloudflare-dns-token written EMPTY (annotated) — the letsencrypt issuers have no zone to solve against; the instance's certificates come from the internal CA"
fi

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
CF_ACCOUNT_DESC="Cloudflare Account ID (an identifier, not a secret)."
CF_ZONE_DESC="Cloudflare Zone ID (an identifier, not a secret)."
# EDGE=local: the four keep their place in the generator —the seed is
# the same in both profiles— but three of them arrive EMPTY, and an
# empty credential whose description still says what it is for is a
# lie the operator reads in Jenkins' own UI. The description is where
# the reason belongs, because that is where it will be seen. (The two
# ids come out empty on their own: the conf writes them empty and the
# validation rejects a local conf that names a zone.)
if [[ "${EDGE:-cloudflare}" == local ]]; then
    CF_JENKINS_DESC="EMPTY under EDGE=local: there is no Cloudflare account, so there is no token. The edge-chequeo job has no zone to read either. The Secret exists because the KSOPS generator lists it in both profiles."
    CF_ACCOUNT_DESC="EMPTY under EDGE=local: this instance names no Cloudflare account."
    CF_ZONE_DESC="EMPTY under EDGE=local: this instance names no Cloudflare zone."
    log_warn "EDGE=local: the 3 Cloudflare credentials of jenkins-system are written EMPTY (each one annotated with why) — the edge-chequeo job that consumes them has no zone to check"
fi
make_enc_secret cloudflare-api-token jenkins-system \
    "$B/platform/jenkins-secrets/secret-cloudflare-api-token.enc.yaml" \
    --label jenkins.io/credentials-type=secretText \
    --annotation "jenkins.io/credentials-description=$CF_JENKINS_DESC" \
    "text=$CF_API"
make_enc_secret cloudflare-account-id jenkins-system \
    "$B/platform/jenkins-secrets/secret-cloudflare-account-id.enc.yaml" \
    --label jenkins.io/credentials-type=secretText \
    --annotation "jenkins.io/credentials-description=$CF_ACCOUNT_DESC" \
    "text=$(materialize cf_account_id "$CF_ACCOUNT_ID")"
make_enc_secret cloudflare-zone-id jenkins-system \
    "$B/platform/jenkins-secrets/secret-cloudflare-zone-id.enc.yaml" \
    --label jenkins.io/credentials-type=secretText \
    --annotation "jenkins.io/credentials-description=$CF_ZONE_DESC" \
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

if [[ "${EDGE:-cloudflare}" == cloudflare ]]; then
    log_ok "AUTOMATIC third parties complete: CF tokens minted over the API, \
3 deploy keys registered via gh, 2 webhooks created, CI credential \
from the gh token — zero browser, zero files moved by hand"
else
    log_ok "AUTOMATIC third parties complete (EDGE=local): 3 deploy keys \
registered via gh, CI credential from the gh token, HMACs and the 8 \
Secrets in place. NOT done, for want of a subject: 3 Cloudflare tokens, \
tokens.enc.yaml and 2 GitHub webhooks"
fi
