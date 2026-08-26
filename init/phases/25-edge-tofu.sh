#!/usr/bin/env bash
# PHASE 25 — the EDGE. WHICH edge is decided by $EDGE, conf of the
# instance, and the two of them do the same job by opposite means:
# somebody has to put the platform within reach and hand the traffic
# to traefik.
#
#   cloudflare — the SaaS side via tofu (D6: ONLY Cloudflare + GitHub;
#     zero K8s resources in tofu). It also produces the KSOPS Secret
#     with the TUNNEL_TOKEN (the token is issued by CF; the init
#     derives it over the API — doc 26 §8.2: T2-E grey, automatable).
#   local — there is no SaaS side to apply: no zone, no tunnel and no
#     Access. What hands the host's 80/443 to traefik is a bridge of
#     four systemd units living ON THE HOST, and installing it is this
#     phase's whole job under that edge (share/systemd/README.md).
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

# ── a gate that has NO SUBJECT under this edge ─────────────────────
# The house's three outcomes are done / already there / NOT EVALUATED,
# and the third one is a WARNING, never an approval: "I could not look"
# is not the same as "it is fine". A step that does not apply says so,
# with the whole reason, and its gate does not vanish in silence — it
# is named, and it is said out loud that under this edge it has nobody
# to measure.
# It does NOT go through gate(): gate() with a `true` would write a
# green line into gates.jsonl for a check that never ran, and a green
# line nobody earned is the one lie this tree does not tell. The record
# carries its own result so that an agent reading the run can tell
# "it passed" from "there was nothing to look at" (the jq of

# ── the edge, by profile ───────────────────────────────────────────
# Everything from here to the commit is Cloudflare's: the tunnel, the
# CNAMEs of the zone, Access in front of argocd and jenkins, and the
# two credentials that come out of that apply. With EDGE=local NONE of
# it has a subject — there is no zone to write a record into, no
# account to open a tunnel under, and no Access to traverse — and its
# place is taken by a bridge on the host: two systemd sockets holding
# 80 and 443 on $EDGE_BIND_IP and handing every byte to traefik's fixed
# ClusterIP.
# What is LOST with local is exactly what only the SaaS gives: arrival
# from the internet without opening a port at home, Cloudflare's
# identity in front of the consoles, and a publicly trusted
# certificate. In exchange the names resolve through sslip.io, TLS is
# signed by the instance's own internal CA, and whoever wants in from
# outside brings their own way in (an SSH tunnel, a VPN).
# ${EDGE:-cloudflare} and not "$EDGE": a conf written before the local
# edge existed does not carry the variable, and it is cloudflare —
# which is the only thing it could have been. It is the same reading
# config_validate does, repeated here because the phase sources the
# conf on its own.
if [[ "${EDGE:-cloudflare}" == local ]]; then
    # A local conf without EDGE_BIND_IP is a bridge with no address to
    # hold. config_validate rejects it, and this says so with a sentence
    # instead of with an unbound-variable trace if one ever gets here by
    # another door:
    [[ -n "${EDGE_BIND_IP:-}" ]] || \
        die "EDGE=local with no EDGE_BIND_IP in the conf — the host bridge has no address to listen on; reconfigure the instance before resuming"

    # The five gates of the Cloudflare path, named one by one with the
    # reason each one has nobody to measure here:
    gate_no_subject "parse-main-tf" \
      "EDGE=local: no tofu env is applied, so there is no main.tf to read a tunnel_name or a list of public_hostnames out of"
    gate_no_subject "token-no-vacio" \
      "EDGE=local: no tunnel is created, so Cloudflare issues no connector token to encrypt for cloudflared"
    gate_no_subject "token-apunta-al-tunnel-nuevo" \
      "EDGE=local: with no token and no tunnel there is no account/tunnel pair to check the token against"
    gate_no_subject "access-st-id-no-vacio" \
      "EDGE=local: there is no Cloudflare Access in front of the consoles, so no service token is issued — under this edge phases 35 and 60 reach the routes with nothing to traverse"
    gate_no_subject "access-st-secret-no-vacio" \
      "EDGE=local: the other half of the same service token that is never issued"

    # ── the host bridge (share/systemd/README.md) ──────────────────
    # Why a bridge and not hostPort: measured against traefik's chart
    # 40.3.0, a hostPort with a hostIP makes traefik listen on the
    # POD's loopback and go deaf to the host. The bridge sidesteps the
    # chart: traefik stays a plain ClusterIP Service, identical in both
    # profiles, and the host-side plumbing lives on the host, where it
    # can be read, restarted and removed without touching the cluster.
    EDGE_UNITS_SRC="$AEGIS_ROOT/share/systemd"
    EDGE_UNITS=(aegis-edge-http.socket  aegis-edge-http.service
                aegis-edge-https.socket aegis-edge-https.service)
    for u in "${EDGE_UNITS[@]}"; do
        [[ -f "$EDGE_UNITS_SRC/$u" ]] || \
            die "$EDGE_UNITS_SRC/$u is missing from the product — the host bridge has no units to install"
    done

    # traefik's ClusterIP is NOT asked of the cluster (there is no
    # traefik yet: ArgoCD installs it in phase 35) and is NOT copied by
    # hand into this file either. It is READ from the manifest that
    # pins it, the same way the cloudflare branch parses tunnel_name out
    # of the env's main.tf: one source, no duplicate. python3+pyyaml
    # and not yq (rule C7 — yq is not part of the pinned userland).
    TRAEFIK_VALUES="$PLATFORM_DIR/k8s/base/ingress/traefik/values.yaml"
    TRAEFIK_IP="$(python3 -c "
import yaml
v = yaml.safe_load(open('$TRAEFIK_VALUES')) or {}
print((((v.get('service') or {}).get('spec')) or {}).get('clusterIP', ''))" 2>/dev/null || true)"
    gate_diag "parse-traefik-clusterip" \
      "ls -l '$TRAEFIK_VALUES' 2>&1; echo 'the bridge needs service.spec.clusterIP of that file: a unit in /etc/systemd cannot ask the apiserver where traefik is today'" \
      test -n "$TRAEFIK_IP"
    log_info "host bridge: $EDGE_BIND_IP:80/443 → traefik at $TRAEFIK_IP"

    for u in "${EDGE_UNITS[@]}"; do
        if cmp -s "$EDGE_UNITS_SRC/$u" "/etc/systemd/system/$u"; then
            log_info "$u already installed, byte for byte"
        else
            run_cmd sudo install -m 0644 "$EDGE_UNITS_SRC/$u" "/etc/systemd/system/$u"
        fi
    done

    # The upstream travels in a file and not baked into the .service so
    # that re-pointing the bridge is editing one line instead of
    # reinstalling the unit (the units read it with EnvironmentFile).
    # The content is built in the phase's tmpfs and installed from
    # there. `install /dev/stdin` was the obvious way and it is a trap:
    # with the destination ALREADY existing it fails with "No such file
    # or directory" (measured, coreutils 9.x) — that is to say it would
    # have worked on the first run and broken on every re-run, which is
    # the worst shape a bug can have.
    _edge_env="$SECRETS_TMP/edge.env"
    cat > "$_edge_env" <<ENVEOF
# Written by phase 25 of the init. Do not edit by hand: the value comes
# from service.spec.clusterIP in the platform repo's
# k8s/base/ingress/traefik/values.yaml, which is what pins traefik to a
# ClusterIP that survives a re-creation.
AEGIS_EDGE_UPSTREAM=$TRAEFIK_IP
ENVEOF
    run_cmd sudo install -d -m 0755 /etc/aegis
    run_cmd sudo install -m 0644 "$_edge_env" /etc/aegis/edge.env

    # The shipped sockets listen on 127.0.0.1: the safe default, and
    # the one the operator overrides in the wizard when they want the
    # platform reachable from their network. That override is a drop-in
    # and not an edit of the unit, so that the unit in the product and
    # the unit on the host stay comparable.
    if [[ "$EDGE_BIND_IP" == "127.0.0.1" ]]; then
        # A PREVIOUS run may have left a drop-in with another address.
        # Left in place it would win over the conf and the bridge would
        # keep listening where it is no longer wanted — silently, since
        # the units themselves would look right.
        for s in aegis-edge-http aegis-edge-https; do
            [[ -f "/etc/systemd/system/$s.socket.d/bind.conf" ]] || continue
            log_warn "a bind drop-in from an earlier run survives on $s and the conf now says $EDGE_BIND_IP — removing it"
            run_cmd sudo rm -f "/etc/systemd/system/$s.socket.d/bind.conf"
        done
    else
        for _pair in http:80 https:443; do
            _sock="aegis-edge-${_pair%%:*}.socket"; _port="${_pair##*:}"
            _bind_conf="$SECRETS_TMP/bind-$_port.conf"
            cat > "$_bind_conf" <<BINDEOF
[Socket]
# The EMPTY ListenStream= resets the list. Without it this drop-in ADDS
# an address instead of replacing one, and the bridge would end up
# listening on 127.0.0.1:$_port as well as on the chosen address.
ListenStream=
ListenStream=$EDGE_BIND_IP:$_port
BINDEOF
            run_cmd sudo install -d -m 0755 "/etc/systemd/system/$_sock.d"
            run_cmd sudo install -m 0644 "$_bind_conf" "/etc/systemd/system/$_sock.d/bind.conf"
        done
        log_warn "the bridge is bound to $EDGE_BIND_IP, which is not loopback: everything that reaches that address reaches the platform, and the host's firewall is the only thing in front of it"
    fi

    run_cmd sudo systemctl daemon-reload
    run_cmd sudo systemctl enable aegis-edge-http.socket aegis-edge-https.socket
    # restart and not start: on a re-run the sockets are ALREADY
    # listening, `start` over a running socket is a no-op, and the old
    # bind would survive the new conf while the gate below measured it.
    run_cmd sudo systemctl restart aegis-edge-http.socket aegis-edge-https.socket

    # ── the gate of this phase under local ─────────────────────────
    # It does not measure that the units exist — that is paperwork. It
    # measures the only thing this phase promises: that the port is
    # open, on the address the conf chose and on no other (a second
    # address on the same port means either a stale drop-in or somebody
    # else's server, and both are worth stopping for).
    # What it deliberately does NOT demand is an answer from traefik:
    # traefik arrives with ArgoCD in phase 35, and a gate that demanded
    # it here would be lying about somebody else's work. Until then a
    # refused connection through the bridge is the honest answer.
    _edge_listens_only_on() {   # <port>
        local got
        got="$(ss -ltn 2>/dev/null | awk -v p=":$1\$" '$4 ~ p {print $4}' \
               | sort -u | tr '\n' ' ')"
        [[ "${got% }" == "$EDGE_BIND_IP:$1" ]]
    }
    _edge_bridge_listens() { _edge_listens_only_on 80 && _edge_listens_only_on 443; }
    if [[ "$CHECK_MODE" == "true" ]]; then
        gate_no_subject "edge-bridge-listens-only-on-bind-ip" \
          "--check installed nothing, so there is no bridge to measure: this gate was NOT EVALUATED, which is a warning and not a pass"
    elif ! command -v ss >/dev/null; then
        gate_no_subject "edge-bridge-listens-only-on-bind-ip" \
          "iproute2's ss is not on this host and the listening address cannot be read: NOT EVALUATED — the bridge may be up or may not, and nothing here knows which"
    else
        gate_diag "edge-bridge-listens-only-on-bind-ip" \
          "ss -ltn 2>&1 | head -20; systemctl --no-pager --full status aegis-edge-http.socket aegis-edge-https.socket 2>&1 | tail -40" \
          _edge_bridge_listens
    fi
else
    # ── DIRTY-CLOUD PRE-CHECK (run #5, finding A) ──────────────────
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

    # ── cloudflare-tunnel: tunnel + config + CNAMEs ────────────────
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

    # ── TUNNEL_TOKEN → KSOPS Secret (without passing over the screen) ───
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

    # ── ACCESS SERVICE TOKEN → store (#87/#88) ─────────────────────
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
fi

# ── commit the encrypted material of phases 15+25 to the repo ──────
# Both edges pass through here. Under local phase 25 contributes
# nothing of its own —the bridge lives in /etc/systemd, not in the
# repo— but phase 15's encrypted material still has to reach the
# remote: everything that follows reads from there and not from disk.
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

if [[ "${EDGE:-cloudflare}" == local ]]; then
    log_ok "Edge applied: the host bridge holds $EDGE_BIND_IP:80/443 and \
hands them to traefik at $TRAEFIK_IP (a refused connection is harmless \
until Traefik — the wait is normal)"
else
    log_ok "Edge applied: GitHub repo configured, tunnel alive (a 503 is \
harmless until Traefik — the wait is normal), token encrypted"
fi
