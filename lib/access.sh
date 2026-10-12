#!/usr/bin/env bash
# lib/access.sh — crossing Cloudflare Access, with ONE implementation
# for the init and for aegis-rotate.
#
# ═══ WHY IT EXISTS (#87) ═══════════════════════════════════════════
#
# Since #76, Access sits in front of argocd.<dom> and jenkins.<dom>.
# From that moment on, EVERY init probe against those hostnames
# stopped measuring what it believes it measures. Measured on
# 2026-08-13:
#
#   $ curl -sI https://argocd.<dom>/
#   HTTP/2 302
#   location: https://<team>.cloudflareaccess.com/cdn-cgi/access/login/...
#   server: cloudflare
#   cf-ray: a2a8aeae4ee814b1-GIG
#
# That 302 is served by the CLOUDFLARE EDGE. It never entered the
# tunnel, never touched traefik, never saw argocd-server. And the
# phase 35 gate accepted it:
#
#   gate "edge-responde" ... | grep -qE '200|404|30[12]'
#                                            ^^^^^^^
#
# A gate named «edge-responde» that stays GREEN with the entire
# cluster switched off. This is disease E in its most expensive form,
# because it is not an absent gate —those are visible— but a gate
# that is present and says PASS. Phase 60 has the mirrored, less
# dangerous flaw: it accepts `^(200|403)$`, so under Access it fails
# RED and stops the init.
#
# ═══ THE WAY OUT ═══════════════════════════════════════════════════
#
# It is NOT to stop measuring the public path. That path IS the one
# that matters: it is where a human comes in, and it is the only one
# that exercises DNS + tunnel + traefik + the app end to end.
# Measuring it from the inside (kubectl port-forward) would prove
# something else.
#
# The way out is the service token that tofu minted together with the
# Access applications (`module.access`, outputs
# access_service_token_client_id/_secret), which phase 25 persists to
# the store as access_st_id / access_st_secret.
#
# And above all: telling «the origin responded» apart from «Access
# intercepted». They are two different facts and until today they gave
# the same signal.
#
# ═══ A27 ═══════════════════════════════════════════════════════════
#
# The secret does not travel through argv (/proc/PID/cmdline is
# readable). curl does not support `--header @file`, but it does
# support `--config file`, which reads the headers from disk. The
# config lives in tmpfs, 600, and is deleted.

# _cf_access_config — prints the path of a curl config carrying the
# two service-token headers, or NOTHING if there is no token in the
# store.
#
# Returning empty is not an error: an instance without Access (or a
# run earlier than phase 25) has to keep working along the same path,
# with no special branches.
_cf_access_config() {
    local id sec cfg
    [[ -n "${STATE_SECRETS:-}" ]] || return 0
    [[ -f "$STATE_SECRETS/access_st_id.enc" ]] || return 0
    [[ -f "$STATE_SECRETS/access_st_secret.enc" ]] || return 0
    id="$(sops -d --input-type binary --output-type binary \
        "$STATE_SECRETS/access_st_id.enc" 2>/dev/null)" || return 0
    sec="$(sops -d --input-type binary --output-type binary \
        "$STATE_SECRETS/access_st_secret.enc" 2>/dev/null)" || return 0
    [[ -n "$id" && -n "$sec" ]] || return 0
    cfg="$(mktemp /dev/shm/aegis-cfacc.XXXXXX)"; chmod 600 "$cfg"
    printf 'header = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n' \
        "$id" "$sec" > "$cfg"
    printf '%s' "$cfg"
}

# curl_access <args...> — curl that crosses Access when there is a
# service token. If there is none, it runs all the same.
curl_access() {
    local cfg rc=0
    cfg="$(_cf_access_config)"
    if [[ -n "$cfg" ]]; then
        curl --config "$cfg" "$@" || rc=$?
        rm -f "$cfg"
    else
        curl "$@" || rc=$?
    fi
    return $rc
}

# edge_origin_responds <url> <regex-of-acceptable-codes>
#
# True ONLY if the ORIGIN responded with an acceptable code. The three
# outcomes are told apart on purpose, because they are three different
# causes and used to give one single signal:
#
#   0  the origin responded and the code is in the pattern
#   1  negative VERDICT — either Access intercepted (and then the
#      origin was NOT measured), or the origin answered something
#      outside the pattern
#   2  TRANSPORT — there was not even a response (DNS, TLS, timeout)
#
# The discriminant for «Access intercepted» is structural, not the
# code: a 302 is a 302 no matter who serves it. What gives Access away
# is WHERE it redirects to — *.cloudflareaccess.com. Comparing codes
# here would be C15 all over again: tying the check to a value that
# changes when the thing moves.
edge_origin_responds() {
    local url="$1" acceptable="$2"
    local cfg out code loc rc=0
    local args=(-sS -m 20 -o /dev/null -w '%{http_code} %{redirect_url}')

    cfg="$(_cf_access_config)"
    [[ -n "$cfg" ]] && args+=(--config "$cfg")
    args+=("$url")
    out="$(curl "${args[@]}" 2>/dev/null)" || rc=$?
    [[ -n "$cfg" ]] && rm -f "$cfg"

    if (( rc != 0 )); then
        printf 'TRANSPORT: curl rc=%d against %s — there was no response\n' \
            "$rc" "$url" >&2
        return 2
    fi

    code="${out%% *}"; loc="${out#* }"
    if [[ "$loc" == *cloudflareaccess.com* ]]; then
        printf 'ACCESS INTERCEPTED %s (%s → cloudflareaccess.com): the ORIGIN was not measured.\n' \
            "$url" "$code" >&2
        printf '  the store service token is missing or not working (access_st_id, access_st_secret).\n' >&2
        return 1
    fi

    grep -qE "$acceptable" <<<"$code" && return 0
    printf 'the ORIGIN answered %s against %s (expected ~ %s)\n' \
        "$code" "$url" "$acceptable" >&2
    return 1
}

# argocd_admin_login_ok <base-url> — the CONSUMER test of the ArgoCD
# admin password that phase 30 takes from the store (#86): the store's
# password GETS IN (200) and a made-up one is REJECTED (401), through
# the edge as a person logs in. The negative half is not decoration:
# without it an ArgoCD that accepted anything would come out green.
# Both requests are built the same way and differ only in the password.
# The password never reaches argv: it goes in a body file in tmpfs, 600,
# shredded on the way out.
argocd_admin_login_ok() {
    local base="$1" d code_ok code_bad
    [[ -f "$STATE_SECRETS/argocd_admin_pass.enc" ]] || {
        printf 'argocd_admin_pass is not in the store: phase 30 did not leave it\n' >&2; return 1; }
    d="$(mktemp -d /dev/shm/aegis-argologin.XXXXXX)"; chmod 700 "$d"
    sops -d --input-type binary --output-type binary \
        "$STATE_SECRETS/argocd_admin_pass.enc" > "$d/good" 2>/dev/null && [[ -s "$d/good" ]] || {
        rm -rf "$d"; printf 'argocd_admin_pass.enc does not decrypt (age key?)\n' >&2; return 1; }
    head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' > "$d/bad"
    for w in good bad; do
        python3 -c 'import json,sys; print(json.dumps({"username": "admin", "password": open(sys.argv[1]).read()}))' \
            "$d/$w" > "$d/$w.json"
    done
    code_ok="$(curl_access -s -o /dev/null -w '%{http_code}' -m 20 -X POST \
        -H 'Content-Type: application/json' -d @"$d/good.json" "$base/api/v1/session" 2>/dev/null)"
    code_bad="$(curl_access -s -o /dev/null -w '%{http_code}' -m 20 -X POST \
        -H 'Content-Type: application/json' -d @"$d/bad.json" "$base/api/v1/session" 2>/dev/null)"
    find "$d" -type f -exec shred -u {} +
    rm -rf "$d"
    if [[ "$code_ok" != 200 ]]; then
        printf 'the store password got %s from ArgoCD (expected 200)\n' "${code_ok:-no answer}" >&2; return 1
    fi
    if [[ "$code_bad" != 401 ]]; then
        printf 'a made-up password got %s (expected 401): the 200 above proves nothing\n' "${code_bad:-no answer}" >&2; return 1
    fi
}

# ═══ A GITHUB DELIVERY, WAITED FOR THE WAY GITHUB DELIVERS ═══════════
#
# GitHub does NOT re-deliver on its own. A delivery that landed on a 530
# from a tunnel still connecting, or on a «failed to connect to host»
# from a resolver that has not seen the CNAME yet, stays failed forever:
# reading it again for minutes measures nothing. Phase 60 learned it in
# the P1.5 audit (2026-07-18) and re-delivered inside its own wait;
# phase 35 kept the old shape —redeliver once, then poll that one
# finished delivery for 180s— and lost alpha-ubuntu on 2026-10-12: a 502
# four seconds after cloudflared connected, and the same redeliver by
# hand, minutes later, 200 OK. Same class twice → one helper.
#
# Only deliveries NEWER than <since_id> count: an old 2xx (a previous
# run, a hook signing with the HMAC from before a rotation) proves
# nothing about the signature that is live now. Delivery ids grow.
#
# What each answer means:
#   2xx    the receiver took it, and with it the signature: pass.
#   400    the receiver REJECTED it — an HMAC out of sync. It converged
#          to an error; re-delivering will not change it: stop now.
#   null   in flight: wait.
#   other  5xx, a connection error (GitHub reports it as 502), a 403/404
#          from an edge still settling: re-deliver it, at most once a
#          minute, until the timeout.

# hook_newest_delivery <owner/repo> <hook_id> [event] — the id of the
# newest delivery (of that event), 0 when there is none. stdout = the id.
hook_newest_delivery() {
    local sel='.'
    [[ -n "${3:-}" ]] && sel="[.[] | select(.event==\"$3\")]"
    local id
    id="$(gh api "repos/$1/hooks/$2/deliveries" --jq "$sel | .[0].id" 2>/dev/null || true)"
    [[ "$id" =~ ^[0-9]+$ ]] && printf '%s\n' "$id" || printf '0\n'
}

# hook_delivery_2xx <owner/repo> <hook_id> <event|""> <since_id> [timeout_s]
hook_delivery_2xx() {
    local repo="$1" hook="$2" event="${3:-}" since="${4:-0}" timeout="${5:-300}"
    local t0=$SECONDS line did code redelivered=0 sel='.'
    [[ -n "$event" ]] && sel="[.[] | select(.event==\"$event\")]"
    while :; do
        line="$(gh api "repos/$repo/hooks/$hook/deliveries" \
            --jq "$sel | .[0] | \"\(.id) \(.status_code)\"" 2>/dev/null || true)"
        did="${line%% *}"; code="${line##* }"
        if [[ "$did" =~ ^[0-9]+$ ]] && (( did > since )); then
            [[ "$code" == 2* ]] && return 0
            if [[ "$code" == 400 ]]; then
                log_warn "delivery $did answered 400: the receiver rejected the signature — re-delivering will not change that"
                return 1
            fi
            if [[ "$code" =~ ^[0-9]+$ ]] && (( (SECONDS - t0) / ${AEGIS_HOOK_REDELIVER_S:-60} >= redelivered )); then
                redelivered=$(( redelivered + 1 ))
                log_warn "delivery $did status=$code — redeliver #$redelivered (GitHub does not re-deliver on its own)"
                gh api -X POST "repos/$repo/hooks/$hook/deliveries/$did/attempts" >/dev/null 2>&1 \
                    || log_warn "the redeliver failed (gh/network) — it is retried on the next lap"
            fi
        fi
        (( SECONDS - t0 >= timeout )) && return 1
        sleep "${AEGIS_HOOK_POLL_S:-10}"
    done
}
