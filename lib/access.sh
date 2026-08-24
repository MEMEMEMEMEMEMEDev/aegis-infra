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
