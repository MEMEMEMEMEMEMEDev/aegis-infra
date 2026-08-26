#!/usr/bin/env bash
# aegis-init lib/config.sh — GUIDED configuration (the operator's
# mission: "the init asks and does; the operator decides and
# confirms — never 'fill in this file'"). Same principle as the
# secrets (generate+guide), applied to the T1 config.
#
# Flow: ensure_config()
#   - valid conf present  → source it and carry on (re-runs and
#     automation: the pre-made .conf IS STILL supported).
#   - no conf (or --configure) → wizard: asks field by field with an
#     explanation + inferred default + immediate validation, shows the
#     summary, confirms, and WRITES the .conf.
set -euo pipefail

CONF_FILE="$AEGIS_HOME/aegis.conf"

# ── validators (one per field type; immediate evidence) ─────────────
_v_domain()  { [[ "$1" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; }
_v_email()   { [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; }
_v_reponame(){ [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }
_v_hex32()   { [[ "$1" =~ ^[0-9a-f]{32}$ ]]; }
_v_nonempty(){ [[ -n "$1" ]]; }
_v_edge()    { [[ "$1" == cloudflare || "$1" == local ]]; }
_v_ip()      { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && python3 -c "
import ipaddress, sys
try: ipaddress.ip_address('$1'); sys.exit(0)
except ValueError: sys.exit(1)"; }
_v_path()    { [[ "$1" == /* || "$1" == "\$HOME"* || "$1" == "$HOME"* ]]; }
_v_svc_ip()  {  # inside k3s's default service CIDR (10.43/16)
    python3 -c "
import ipaddress, sys
try:
    ip = ipaddress.ip_address('$1')
    sys.exit(0 if ip in ipaddress.ip_network('10.43.0.0/16') else 1)
except ValueError:
    sys.exit(1)"
}

# ── ask <var> <default> <validator> <explanation...> ────────────────
# Asks with the default in brackets (enter = accept), validates on the
# spot, retries until the value is valid.
ask() {
    local var="$1" def="$2" validator="$3"; shift 3
    printf '\n\033[1;36m── %s ──\033[0m\n' "$var"
    printf '%s\n' "$@"
    # P0.2 audit: with stdin closed, read failed, ans stayed empty, the
    # validator failed and the `while :` retried FOREVER (infinite
    # busy-loop — errexit is suppressed by the caller's || context).
    # `read || die` cuts the EOF short; the cap on attempts cuts short
    # the persistently invalid value:
    local ans tries=0
    while :; do
        if [[ -n "$def" ]]; then
            read -rp "  ${var} [${def}]: " ans || \
                die "stdin closed in the wizard — for unattended runs: a pre-made aegis-init.conf + --non-interactive"
            ans="${ans:-$def}"
        else
            read -rp "  ${var}: " ans || \
                die "stdin closed in the wizard — for unattended runs: a pre-made aegis-init.conf + --non-interactive"
        fi
        if "$validator" "$ans"; then break; fi
        tries=$(( tries + 1 ))
        (( tries >= 3 )) && die "3 invalid values in a row for $var — aborting the wizard (check the format asked for above)"
        log_warn "invalid value for $var — again ($tries/3)"
    done
    printf -v "$var" '%s' "$ans"
}

# ── the wizard ──────────────────────────────────────────────────────
config_wizard() {
    printf '\n\033[1m════ GUIDED CONFIGURATION OF AEGIS v2 ════\033[0m\n'
    printf 'Everything here is T1 (public/known) — ZERO secrets.\n'
    printf 'Enter accepts the default in brackets.\n'

    # ── the edge, FIRST: it decides which questions follow ──────────
    # 02 §3.2: the local profile is not another branch of the init, it is
    # ANOTHER VALUE of the conf. Everything downstream reads EDGE; no
    # phase asks "which profile am I".
    ask EDGE "cloudflare" _v_edge \
      "How the platform is reached from outside:" \
      "  cloudflare — a zone of yours, a tunnel and Access in front" \
      "               (needs an active zone and its two IDs)." \
      "  local      — no zone and no tunnel: a bridge on the host," \
      "               names through sslip.io and TLS from aegis' own" \
      "               internal CA. This is the profile of the lab VPS" \
      "               and of any machine with no domain."

    if [[ "$EDGE" == local ]]; then
        ask EDGE_BIND_IP "127.0.0.1" _v_ip \
          "Address the host's bridge listens on (80/443)." \
          "  127.0.0.1  loopback: reachable only from this machine," \
          "             or through an SSH tunnel. The safe default." \
          "  <LAN IP>   opt-in: reachable from your network too."
    else
        EDGE_BIND_IP=""
    fi

    # GH_OWNER: inferred from the already-authenticated gh session (the
    # phase 00 gate demands it; here it may not have run yet → best
    # effort)
    local gh_user=""
    gh_user="$(gh api user --jq .login 2>/dev/null || true)"
    ask GH_OWNER "$gh_user" _v_reponame \
      "GitHub owner (user or org) that owns the working repos." \
      "$( [[ -n "$gh_user" ]] && echo '  (inferred from your gh session)' )"

    ask PLATFORM_REPO "ops-stack-v2" _v_reponame \
      "PLATFORM repo that the init CREATES and uses (GitOps reads from here)." \
      "ISOLATION: it is a DISPOSABLE v2 test repo — do NOT point it" \
      "at the real ops-stack: the init writes commits, tags and" \
      "settings to it. The default separates v2 from v1 on purpose."

    ask APP_REPO "hello-aegis-v2" _v_reponame \
      "Repo of the canary APP that the init CREATES and seeds (CI" \
      "writes builds to it and commits the digest of every deploy)." \
      "Same isolation: do NOT point it at the real hello-aegis."

    if [[ "$EDGE" == local ]]; then
        # sslip.io resolves <a-b-c-d>.sslip.io to a.b.c.d with no zone
        # of your own and nothing to configure in CoreDNS. It is a
        # NAME for an address, not a domain you own.
        ask ROOT_DOMAIN "${EDGE_BIND_IP//./-}.sslip.io" _v_domain \
          "Name the platform answers to. With EDGE=local the default" \
          "resolves through sslip.io to ${EDGE_BIND_IP} without owning" \
          "any zone: argocd.<name>, jenkins.<name> all land on the" \
          "host's bridge. If sslip.io is unreachable from this machine," \
          "any name works with an /etc/hosts entry."
    else
        ask ROOT_DOMAIN "" _v_domain \
          "Root domain (e.g. mydomain.com). It MUST be an active zone" \
          "in your Cloudflare account (the tunnel and the DNS live there)." \
          "Subdomains the init is going to use: argocd.<domain>," \
          "jenkins.<domain>."
    fi

    local git_email=""
    git_email="$(git config --global user.email 2>/dev/null || true)"
    ask ACME_EMAIL "$git_email" _v_email \
      "Email for the Let's Encrypt ACME registration (certificate" \
      "expiry notices)."

    ask KUBE_CONTEXT_EXPECTED "default" _v_nonempty \
      "Name of the kubectl context that the init DEMANDS before" \
      "touching the cluster (A11: the someone-else's-kubeconfig" \
      "pothole). A freshly installed k3s is called 'default'."

    ask REGISTRY_CLUSTER_IP "10.43.179.123" _v_svc_ip \
      "FIXED ClusterIP of the internal registry. It must fall inside" \
      "k3s's service CIDR (default 10.43.0.0/16) and it is paired" \
      "with the SAN of the registry's TLS certificate (the kubelet" \
      "does not resolve .svc — the host's trust goes through this" \
      "IP). The range is validated on the spot."

    ask AEGIS_WORKSPACE "\$HOME/aegis" _v_path \
      "The operator's workspace (for direnv's .envrc after the init)." \
      "On a validation VM the default is fine."

    if [[ "$EDGE" == local ]]; then
        # Asked for and left empty ON PURPOSE, not omitted: the conf has
        # ONE shape, and a variable that exists empty says "this profile
        # does not use it". A variable that is missing says nothing, and
        # every consumer would have to guess with ${CF_ZONE_ID:-}.
        CF_ACCOUNT_ID="" CF_ZONE_ID=""
        printf '\nEDGE=local: no Cloudflare account and no zone are asked for.\n'
    else
        printf '\nThe TWO Cloudflare IDs are public, but you have to go\n'
        printf 'looking for them: dash.cloudflare.com → click your zone (%s)\n' \
            "${ROOT_DOMAIN}"
        printf '→ Overview tab → right-hand column, "API" section:\n'
        printf '  - Zone ID\n  - Account ID\nBoth are 32 hex.\n'
        ask CF_ACCOUNT_ID "" _v_hex32 \
          "Cloudflare Account ID (32 hex, API section of the Overview)."
        ask CF_ZONE_ID "" _v_hex32 \
          "Zone ID of the ${ROOT_DOMAIN} zone (32 hex, same section)."
    fi

    # ── summary + confirmation ──────────────────────────────────────
    printf '\n\033[1m════ SUMMARY ════\033[0m\n'
    local v
    for v in EDGE EDGE_BIND_IP GH_OWNER PLATFORM_REPO APP_REPO ROOT_DOMAIN ACME_EMAIL \
             KUBE_CONTEXT_EXPECTED REGISTRY_CLUSTER_IP AEGIS_WORKSPACE \
             CF_ACCOUNT_ID CF_ZONE_ID; do
        printf '  %-22s = %s\n' "$v" "${!v}"
    done
    local ok
    read -rp $'\nShall I write this config? [Y/n] ' ok || \
        die "stdin closed at the wizard's confirmation"
    [[ "${ok:-Y}" =~ ^[SsYy]?$ ]] || { log_warn "wizard cancelled"; return 1; }

    # ── atomic write of the .conf ───────────────────────────────────
    local tmp; tmp="$(mktemp)"
    {
        echo "# aegis-init.conf — GENERATED by the wizard ($(date -u +%F))."
        echo "# Edit by hand only for automation/re-runs;"
        echo "# regenerate with: $AEGIS_ROOT/init/aegis-init.sh --configure"
        for v in EDGE EDGE_BIND_IP GH_OWNER PLATFORM_REPO APP_REPO ROOT_DOMAIN \
                 ACME_EMAIL KUBE_CONTEXT_EXPECTED REGISTRY_CLUSTER_IP \
                 CF_ACCOUNT_ID CF_ZONE_ID; do
            # ${!v:-}: under EDGE=local the two Cloudflare ids and, under
            # cloudflare, EDGE_BIND_IP are deliberately EMPTY. They are
            # still WRITTEN, so the conf has one shape and no consumer has
            # to guess whether a variable is missing or empty.
            printf '%s="%s"\n' "$v" "${!v:-}"
        done
        # AEGIS_WORKSPACE may contain $HOME on purpose (no hard
        # quoting — it expands when sourced):
        printf 'AEGIS_WORKSPACE="%s"\n' "$AEGIS_WORKSPACE"
    } > "$tmp"
    mv "$tmp" "$CONF_FILE"
    log_ok "config written to $CONF_FILE"
}

# ── validation of an existing conf (for re-runs) ────────────────────
config_validate() {
    # shellcheck source=/dev/null
    source "$CONF_FILE"
    local missing=() v
    # A conf with no EDGE was written before 2026-08-26: it is cloudflare,
    # which is the only thing it could have been.
    EDGE="${EDGE:-cloudflare}"
    _v_edge "$EDGE" || { log_warn "EDGE must be cloudflare or local (it says '$EDGE')"; return 1; }
    for v in GH_OWNER PLATFORM_REPO APP_REPO ROOT_DOMAIN ACME_EMAIL \
             KUBE_CONTEXT_EXPECTED REGISTRY_CLUSTER_IP; do
        [[ -n "${!v:-}" ]] || missing+=("$v")
    done
    # The two Cloudflare ids are REQUIRED under cloudflare and must be
    # EMPTY under local: a leftover zone id in a local conf is a phase
    # reaching for a zone nobody asked it to touch.
    if [[ "$EDGE" == cloudflare ]]; then
        for v in CF_ACCOUNT_ID CF_ZONE_ID; do
            [[ -n "${!v:-}" ]] || missing+=("$v")
        done
    else
        [[ -n "${EDGE_BIND_IP:-}" ]] || missing+=(EDGE_BIND_IP)
        if [[ -n "${CF_ACCOUNT_ID:-}${CF_ZONE_ID:-}" ]]; then
            log_warn "EDGE=local but CF_ACCOUNT_ID/CF_ZONE_ID carry a value — a local edge must not name a zone"
            return 1
        fi
    fi
    if ((${#missing[@]})); then
        log_warn "incomplete conf — missing: ${missing[*]}"
        return 1
    fi
    _v_domain "$ROOT_DOMAIN" || { log_warn "invalid ROOT_DOMAIN"; return 1; }
    _v_svc_ip "$REGISTRY_CLUSTER_IP" || {
        log_warn "REGISTRY_CLUSTER_IP outside 10.43.0.0/16"; return 1; }
    return 0
}

# ── entrypoint ──────────────────────────────────────────────────────
ensure_config() {
    if [[ "${FORCE_CONFIGURE:-false}" == "true" || ! -f "$CONF_FILE" ]]; then
        # P0.1 audit: the wizard needs somebody to answer — unattended,
        # the .conf is a PREREQUISITE, and this is where that is said:
        ni_mode && die "--non-interactive without $CONF_FILE — the wizard does not run unattended; pre-create the conf (run '$AEGIS_ROOT/init/aegis-init.sh --configure' once with a terminal, or write it by hand from the template)"
        [[ -f "$CONF_FILE" ]] && log_info "regenerating config (--configure)"
        config_wizard || die "without a config there is no going on"
    fi
    config_validate || {
        log_warn "the existing conf does not validate — running the wizard"
        config_wizard || die "without a valid config there is no going on"
        config_validate || die "config is still invalid after the wizard"
    }
    log_ok "valid config: domain=$ROOT_DOMAIN owner=$GH_OWNER \
repos=$PLATFORM_REPO/$APP_REPO (disposable)"
}
