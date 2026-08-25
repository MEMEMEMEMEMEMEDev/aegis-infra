#!/usr/bin/env bash
# tofu-apply.sh v2 — MANDATORY wrapper for every tofu call (A14).
# Decrypts tofu/secrets/tokens.enc.yaml IN MEMORY and exports the
# TF_VARs. KEY CHANGE vs v1 (D2/D6/D10): tofu v2 manages ONLY
# Cloudflare — no K8s resources and no GitHub (repos/settings/webhooks
# go through gh api in the init, phases 12/15). Total surface of the
# wrapper: ONE token (CF api), rotatable through a third party. Neither
# the age key, nor deploy keys, nor a PAT, nor HMAC pass through here.
#
# Usage:  ./tofu-apply.sh -chdir=envs/<env> <plan|apply|output> [...]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKENS="$HERE/secrets/tokens.enc.yaml"

# ALL diagnostics to STDERR — the wrapper's stdout is SACRED (H4):
# `exec tofu "$@"` lets tofu's REAL stdout through, and the callers
# capture read subcommands with $() — e.g. `output -raw tunnel_id`
# in phase 25. A log line on stdout contaminates that capture (run #6,
# bug 3: TUNNEL_ID ended up with the header glued on → the token gate
# never matched). Same class as log_* in lib/common.sh.
log()  { printf '[tofu-wrapper] %s\n' "$*" >&2; }
die()  { printf '[tofu-wrapper] ERROR: %s\n' "$*" >&2; exit 1; }

command -v tofu >/dev/null || die "tofu is not in PATH"

# A TOKEN ALREADY EXPORTED BY THE CALLER TAKES PRECEDENCE, just like the
# other three TF_VARs further down. It is not an exception: it is the
# SAME rule, applied to the fourth value.
#
# It exists so that CI can run this WITHOUT THE AGE KEY. The edge-apply
# job receives only the Cloudflare token as a Jenkins credential, and
# with that the wrapper does not need to decrypt anything. The root of
# trust —the age key— does NOT enter CI, ever.
#
# This is exactly what D6 shrank tofu's surface for: a single
# third-party token, rotatable without ceremony. The worst case if that
# token leaks is a compromised DNS zone, not the whole platform.
if [[ -n "${TF_VAR_cloudflare_api_token:-}" ]]; then
    log "token injected by the caller — nothing is decrypted (CI mode)"
    export TF_VAR_cloudflare_api_token
else
    command -v sops >/dev/null || die "sops is not in PATH"
    [[ -n "${SOPS_AGE_KEY_FILE:-}" ]] \
        || die "SOPS_AGE_KEY_FILE not exported (A2: do not trust direnv)"
    [[ -f "$TOKENS" ]] || die "$TOKENS does not exist"

    # decryption in memory; extraction with python3 (not yq — C7):
    decrypted="$(sops -d "$TOKENS")" || die "sops -d failed (age key?)"

    get() {
        printf '%s' "$decrypted" | python3 -c "
import sys, yaml
doc = yaml.safe_load(sys.stdin)
v = doc
for k in '$1'.split('.'):
    v = v[k]
print(v['value'] if isinstance(v, dict) else v)"
    }

    export TF_VAR_cloudflare_api_token="$(get cloudflare.api_token)"
    # #76: a SEPARATE token for Access. If the caller already exported
    # it (CI mode) it takes precedence, like the others — but the
    # edge-apply job should NOT receive it: the separation exists so
    # that a compromised CI cannot disable Access.
    export TF_VAR_cloudflare_access_token="${TF_VAR_cloudflare_access_token:-$(get cloudflare.access_token)}"
    unset decrypted
fi

# ── T1 values derivable from the config (D11: what is known is
#    DERIVED, never asked again). Run #4: the wrapper injected only
#    the token and tofu stopped to ask INTERACTIVELY for
#    account_id/zone_id/domain — three values the wizard had already
#    captured. Source: the workspace's aegis-init.conf (or an explicit
#    AEGIS_INIT_CONF); a TF_VAR_* already exported by the caller takes
#    precedence. ──────────────────────────────────────────────
AEGIS_CONF="${AEGIS_INIT_CONF:-$HERE/../../init/aegis-init.conf}"
if [[ -f "$AEGIS_CONF" ]]; then
    # shellcheck source=/dev/null
    source "$AEGIS_CONF"
    export TF_VAR_cloudflare_account_id="${TF_VAR_cloudflare_account_id:-${CF_ACCOUNT_ID:-}}"
    export TF_VAR_cloudflare_zone_id="${TF_VAR_cloudflare_zone_id:-${CF_ZONE_ID:-}}"
    export TF_VAR_root_domain="${TF_VAR_root_domain:-${ROOT_DOMAIN:-}}"
    # #76: the mail of the operator allowed in through Access. It comes
    # from ACME_EMAIL and not from a key of its own on purpose: it is
    # the same human, and two sources for one value is how they drift.
    export TF_VAR_operador_email="${TF_VAR_operador_email:-${ACME_EMAIL:-}}"
fi

# guard: EVERY injectable var present and with no placeholder — a
# missing TF_VAR = an interactive tofu prompt = D11 broken (better to
# abort with evidence than to hang waiting for someone to type):
INJECTED=(TF_VAR_cloudflare_api_token TF_VAR_cloudflare_access_token \
          TF_VAR_cloudflare_account_id \
          TF_VAR_cloudflare_zone_id TF_VAR_root_domain \
          TF_VAR_operador_email)
for v in "${INJECTED[@]}"; do
    [[ "${!v:-}" == PLACEHOLDER_* ]] && die "$v is still a placeholder"
    [[ -z "${!v:-}" ]] && die "$v empty — is $AEGIS_CONF missing, or the key in the config? (export it as $v to override)"
done

# ── THE STATE (#46) ───────────────────────────────────────────────
#
# The state lives ENCRYPTED AND VERSIONED in terraform.tfstate.enc.json,
# and the plaintext .tfstate is a working file that never enters git.
#
# WHY NOT IN A REMOTE BACKEND. The state holds `tunnel_secret` and the
# Cloudflare token IN THE CLEAR. A backend with a credential of its own
# would become the custodian of a PLATFORM secret: whoever obtains it
# brings up their own cloudflared and receives the traffic of every
# hostname. Today the worst case if the CF token leaks is a compromised
# DNS zone; with the state outside it would become the entire traffic.
# Encrypting it with the age key adds NOTHING new to look after: that
# key is already the root of trust and is already needed to recover.
#
# WHAT THIS COSTS, said plainly: CI cannot apply the edge, because
# decrypting needs the age key and the age key does not enter CI (§4 of
# the protocol). Applying the edge is an operator command. In exchange,
# the drift check does NOT use the state: it asks Cloudflare which
# hostnames exist and compares them against the ones derived from the
# contracts. See `aegis check`.
ENV_ARG=""
for a in "$@"; do
    case "$a" in -chdir=*) ENV_ARG="${a#-chdir=}" ;; esac
done

# An ABSOLUTE -chdir turned "$HERE/$ENV_ARG" into a garbage path and ALL
# the encrypted-state machinery (#46) was skipped IN SILENCE: phase 85
# applied three times against the plaintext state while the enc.json
# aged without anybody knowing (measured 2026-08-21: serial 12 in the
# plaintext one, 11 in the encrypted one, and the rotation verifier
# overwriting the good one with the old one). Never silence: if it
# falls under this tree it is normalised; if not, it dies saying why.
if [[ -n "$ENV_ARG" && "$ENV_ARG" == /* ]]; then
    if [[ "$ENV_ARG" == "$HERE"/* ]]; then
        ENV_ARG="${ENV_ARG#"$HERE"/}"
    else
        die "absolute -chdir outside $HERE ($ENV_ARG): the encrypted state would not know where to live (#46) — use a path relative to tofu/"
    fi
fi

PLAIN="" ; ENCRYPTED="" ; FINGERPRINT_BEFORE=""
if [[ -n "$ENV_ARG" ]]; then
    PLAIN="$HERE/$ENV_ARG/terraform.tfstate"
    ENCRYPTED="$PLAIN.enc.json"
fi

fingerprint() { [[ -f "$1" ]] && sha256sum "$1" | cut -d' ' -f1 || echo "(does not exist)"; }

if [[ -n "$ENCRYPTED" && -f "$ENCRYPTED" ]]; then
    if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then
        die "there is encrypted state in $(basename "$ENCRYPTED") but SOPS_AGE_KEY_FILE is not exported.
       The state CANNOT be read without the age key, and that is on purpose (#46).
       If this is CI: this job cannot apply the edge. The drift check that
       DOES run without the age key lives in aegis check."
    fi
    command -v sops >/dev/null || die "sops is not in PATH"
    # Decrypts to a 600 file and NOT to stdout: the wrapper's stdout is
    # sacred (H4) and, besides, the tunnel_secret travels in there.
    umask 077
    sops -d "$ENCRYPTED" > "$PLAIN" || die "sops -d of the state failed (is the age key the right one?)"
    log "state decrypted ($(python3 -c "import json,sys; print(len(json.load(open('$PLAIN')).get('resources',[])))") resources)"
fi
[[ -n "$PLAIN" ]] && FINGERPRINT_BEFORE="$(fingerprint "$PLAIN")"

# `tofu` and not `exec tofu`: we have to come back AFTERWARDS to
# re-encrypt. stdout still passes straight through —the callers capture
# `output -raw tunnel_id` with $()— because nothing is redirected here.
log "TF_VARs injected (${#INJECTED[@]}). Delegating to tofu: $*"
set +e
tofu "$@"
RC=$?
set -e

# Re-encrypt ONLY if the state changed. sops produces different text on
# every run even when the content is identical (a fresh data key), so
# re-encrypting always would fill git with diffs that mean nothing —
# and a diff that means nothing is a diff that stops being read.
if [[ -n "$PLAIN" && -f "$PLAIN" && "$(fingerprint "$PLAIN")" != "$FINGERPRINT_BEFORE" ]]; then
    command -v sops >/dev/null || die "the state changed and sops is not in PATH"
    umask 077
    sops -e --input-type json --output-type json \
         --filename-override "$ENCRYPTED" "$PLAIN" > "$ENCRYPTED.tmp" \
        || die "sops -e of the state failed"
    mv "$ENCRYPTED.tmp" "$ENCRYPTED"
    log "state re-encrypted -> $(basename "$ENCRYPTED")  — COMMIT IT"
    log "  without that commit, the next recovery does not know this exists."
fi

exit $RC
