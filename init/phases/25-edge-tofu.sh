#!/usr/bin/env bash
# PHASE 25 — the SaaS side via tofu (D6: ONLY Cloudflare + GitHub;
# zero K8s resources in tofu). It also produces the KSOPS Secret with
# the TUNNEL_TOKEN (the token is issued by CF; the init derives it
# over the API — doc 26 §8.2: T2-E grey, automatable).
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
# CR-6 in-VM report #14: this phase MUTATES the platform repo — the
# local clone may be behind the remote (a manual fix by the operator
# on GitHub during a resume). Synchronize BEFORE touching anything:
platform_repo_sync
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/aegis.key}"

TOFU="$PLATFORM_DIR/tofu/tofu-apply.sh"
TUNNEL_ENV="$PLATFORM_DIR/tofu/envs/cloudflare-tunnel"
secrets_workdir

# (D10: the GitHub side no longer goes through tofu — repos+B4
#  settings were done by phase 12 and the webhook by phase 15, all via
#  idempotent gh api. tofu was left Cloudflare-only: one state, one
#  token.)

# ── DIRTY-CLOUD PRE-CHECK (run #5, finding A) ──────────────────────
# The snapshot wipes the VM but NOT the cloud: a same-named tunnel
# from a previous run makes tofu fail with a 409 and — worse — makes
# an invalid token get encrypted and only blow up 3 phases later
# (cloudflared CrashLoop). Greenfield = detect the leftovers HERE,
# offer to clean them (RED: it deletes in Cloudflare) and only then
# create.
# Single source for the name/hostnames: the env's main.tf (they are
# parsed, not duplicated):
TUNNEL_NAME="$(grep -oP 'tunnel_name\s*=\s*"\K[^"]+' "$TUNNEL_ENV/main.tf")"
HOSTS="$(grep -oP 'public_hostnames\s*=\s*\[\K[^]]*' "$TUNNEL_ENV/main.tf" \
         | tr -d '" ' | tr ',' ' ')"
gate "parse-main-tf" bash -c "[[ -n '$TUNNEL_NAME' && -n '$HOSTS' ]]"
CF_API="$(restore_secret cf_api_token)" || \
    die "cf_api_token is not in the store — resume with --from 15"
# W-03/SEC-12: CF token through a curl config in tmpfs (600), not
# through argv:
_cf_cfg="$SECRETS_TMP/cf_api.curlcfg"
( umask 077; printf 'header = "Authorization: Bearer %s"\n' "$(cat "$CF_API")" > "$_cf_cfg" )
_cf() { curl -sS -K "$_cf_cfg" -H 'Content-Type: application/json' "$@"; }
CFB="https://api.cloudflare.com/client/v4"
TID_PREV="$(_cf "$CFB/accounts/$CF_ACCOUNT_ID/cfd_tunnel?name=$TUNNEL_NAME&is_deleted=false" \
            | jq -r '.result[0].id // empty')"
CNAMES_PREV=()
for h in $HOSTS; do
    rid="$(_cf "$CFB/zones/$CF_ZONE_ID/dns_records?type=CNAME&name=$h.$ROOT_DOMAIN" \
           | jq -r '.result[0].id // empty')"
    [[ -n "$rid" ]] && CNAMES_PREV+=("$h.$ROOT_DOMAIN:$rid")
done
if [[ -n "$TID_PREV" || ${#CNAMES_PREV[@]} -gt 0 ]]; then
    log_warn "leftovers from a previous run in Cloudflare (dirty cloud):"
    [[ -n "$TID_PREV" ]] && log_warn "  tunnel '$TUNNEL_NAME' = $TID_PREV"
    for c in "${CNAMES_PREV[@]}"; do log_warn "  CNAME ${c%%:*}"; done
    gate_red "DELETE them from Cloudflare and recreate clean (greenfield RECREATES; if these resources belonged to ANOTHER project, ABORT)"
    if [[ -n "$TID_PREV" ]]; then
        _cf -X DELETE "$CFB/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$TID_PREV/connections" >/dev/null
        _cf -X DELETE "$CFB/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$TID_PREV" \
            | jq -e '.success == true' >/dev/null || die "could not delete the previous tunnel $TID_PREV"
        log_ok "previous tunnel deleted"
    fi
    for c in "${CNAMES_PREV[@]}"; do
        _cf -X DELETE "$CFB/zones/$CF_ZONE_ID/dns_records/${c##*:}" \
            | jq -e '.success == true' >/dev/null || die "could not delete the CNAME ${c%%:*}"
        log_ok "CNAME ${c%%:*} deleted"
    done
    # BUG 2 (run #6): cleaning the cloud is only HALF of it. The LOCAL
    # terraform.tfstate survives on the VM's disk across --from 25
    # (git ignores it; the disk does not). If it stays, tofu does a
    # "Refreshing state" over the tunnel we JUST deleted, takes it for
    # existing and does a PUT .../cfd_tunnel/<id>/configurations → 404
    # "Tunnel not found". BOTH halves of the greenfield are cleaned
    # TOGETHER: when deleting in the cloud, purge the local state so
    # that the apply below recreates from scratch. (The
    # clean-cloud/dirty-state case caused by a manual deletion in the
    # dashboard is covered by tofu's refresh: remote 404 → drop the
    # resource → recreate.)
    rm -f "$TUNNEL_ENV/terraform.tfstate" "$TUNNEL_ENV/terraform.tfstate.backup"
    log_ok "the env's local tfstate purged — cloud and local state in sync"
fi

# ── cloudflare-tunnel: tunnel + config + CNAMEs ────────────────────
# FATAL and explicit apply (finding A: a 409 here poisons the token
# and the symptom appears 3 phases later — never continue after an
# error):
log_info "tofu cloudflare-tunnel (edge only)"
run_cmd "$TOFU" -chdir="$TUNNEL_ENV" init -input=false || \
    die "tofu init failed — do NOT continue"
run_cmd "$TOFU" -chdir="$TUNNEL_ENV" apply -auto-approve || \
    die "tofu apply failed — do NOT continue: a partial apply leaves the token/CNAMEs poisoned (409 = leftovers in the cloud; see the pre-check above and VALIDACION §1.8)"
# W-03/SEC-02: the tfstate holds the TUNNEL_TOKEN and the
# tunnel_secret in the clear — set to 600 as soon as it is written
# (previously 0664, readable by group/others). Encryption at rest =
# debt W-09 (decision-repos-git.md §5):
for f in "$TUNNEL_ENV"/terraform.tfstate "$TUNNEL_ENV"/terraform.tfstate.backup; do
    [[ -f "$f" ]] && chmod 600 "$f"
done

# ── TUNNEL_TOKEN → KSOPS Secret (without passing over the screen) ──
"$TOFU" -chdir="$TUNNEL_ENV" output -raw tunnel_token \
    > "$SECRETS_TMP/tunnel_token"
gate "token-no-vacio" bash -c \
    "[[ \$(wc -c < '$SECRETS_TMP/tunnel_token') -gt 50 ]]"
# REAL validation of the token BEFORE encrypting it (finding A: the
# invalid token only blew up in cloudflared's CrashLoop, phase 35).
# The connector token is base64(JSON{a,t,s}); it must point at THIS
# account and at the tunnel THIS apply created (a structural
# shape-check, without printing the secret):
TUNNEL_ID="$("$TOFU" -chdir="$TUNNEL_ENV" output -raw tunnel_id)"
gate "token-apunta-al-tunnel-nuevo" bash -c \
  "base64 -d < '$SECRETS_TMP/tunnel_token' 2>/dev/null \
   | jq -e --arg a '$CF_ACCOUNT_ID' --arg t '$TUNNEL_ID' \
       '.a == \$a and .t == \$t and (.s | length > 0)' >/dev/null"
make_enc_secret cloudflared-tunnel-token infra-edge \
    "$PLATFORM_DIR/k8s/base/ingress/cloudflare-tunnel/secret-cloudflared-tunnel-token.enc.yaml" \
    "TUNNEL_TOKEN=$SECRETS_TMP/tunnel_token"

# ── ACCESS SERVICE TOKEN → store (#87/#88) ────────────────────────
# The same apply above raises Cloudflare Access in front of
# argocd.<dom> and jenkins.<dom> (module.access, #76). That leaves
# phases 35 and 60 probing hostnames that now answer 302 to
# Cloudflare's login — and that 302 is served by the edge, without
# entering the tunnel. Phase 35 accepted it as "edge-responde" (green
# with the cluster switched off) and phase 60 rejected it (red over a
# healthy Jenkins). Both need to traverse Access, and for that they
# need THIS.
#
# It does NOT go into a K8s Secret: nobody INSIDE the cluster uses it.
# It lives in the store because the consumers are the init itself
# (phases 35/60) and aegis-rotate --verificar — both run on the
# operator's machine and both have the age key. Sending it to the
# cluster would be handing a credential to a place that does not need
# it.
#
# Until today these two values had been put there by a hand in #76: a
# new instance reached phase 35 without them and the gate lied.
# Both persist_secret calls go LITERAL and not in a for. Check 89 of
# verify-static.sh extracts the store's names by parsing these calls,
# and its declared blind spot is exactly
# `persist_secret "$variable"`: a loop here would leave two new
# credentials out of the rotation inventory with nothing to warn
# about it. Two repeated lines cost less than a blind spot.
( umask 077
  "$TOFU" -chdir="$TUNNEL_ENV" output -raw access_service_token_client_id \
      > "$SECRETS_TMP/access_st_id"
  "$TOFU" -chdir="$TUNNEL_ENV" output -raw access_service_token_client_secret \
      > "$SECRETS_TMP/access_st_secret" )
# a LENGTH shape-check, not a format one: the shape of the client_id
# (`<uuid>.access`) is defined by Cloudflare, and tying a gate to it
# is C15. Empty IS a hard failure — it means module.access was not
# applied, and then Access is not in place:
gate "access-st-id-no-vacio" bash -c \
    "[[ \$(wc -c < '$SECRETS_TMP/access_st_id') -gt 20 ]]"
gate "access-st-secret-no-vacio" bash -c \
    "[[ \$(wc -c < '$SECRETS_TMP/access_st_secret') -gt 20 ]]"
persist_secret access_st_id     "$SECRETS_TMP/access_st_id"
persist_secret access_st_secret "$SECRETS_TMP/access_st_secret"
log_ok "Access service token persisted to the store — phases 35 and 60 can traverse it"

# EDGE CASE (Q2): if this apply RECREATED a previous tunnel, orphan
# CNAMEs/records from the old one may remain. tofu owns its own; the
# foreign ones are cleaned by hand. The DNS gate is in phase 35 (once
# there is a backend that answers).

# ── commit the encrypted material of phases 15+25 to the repo ──────
log_info "committing encrypted secrets + tfvars to the platform repo"
# class F audit: no || true — an empty staged set is a legitimate
# no-op, a FAILED commit with staged changes kills the phase here
# (not 2 phases later):
git_commit_if_changes "$PLATFORM_DIR" \
    "feat(bootstrap): initial encrypted secrets + edge applied"
# push of the new encrypted files (the remote exists and was seeded by
# phase 12). BLOCKING: everything that follows (ArgoCD, KSOPS) reads
# from the remote — without a push, later phases run against an old
# repo.
run_cmd retry_net 3 git -C "$PLATFORM_DIR" push -u origin main || \
  die "push failed — check the remote/deploy key and resume with --from 25"

log_ok "Edge applied: GitHub repo configured, tunnel alive (a 503 is \
harmless until Traefik — the wait is normal), token encrypted"
