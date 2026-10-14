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
# THE PATH IS THE INSTANCE'S, and it was the previous lineage's until
# 2026-08-31. This wrapper looked for `init/aegis-init.conf`, which is
# where the config lived when the product and the instance were one
# directory. In this artifact they are two: the config is
# `$AEGIS_HOME/aegis.conf`, and `$HERE/../..` from platform/tofu IS
# $AEGIS_HOME.
#
# Nobody had noticed because the rehearsal that exercised this wrapper
# ran with EDGE=local, where there is no tunnel env to apply. The
# first cloudflare run found it on its first `tofu init`, with a
# message that named the file it could not find — which is the one
# thing that made it a five-minute diagnosis instead of an afternoon.
AEGIS_CONF="${AEGIS_INIT_CONF:-$HERE/../../aegis.conf}"
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
# WHICH VARIABLES, DERIVED FROM THE ENV BEING APPLIED. This list used
# to be fixed — six names demanded of every env — and on 2026-08-31 the
# first apply of `envs/data-r2` died on `TF_VAR_cloudflare_access_token
# empty`: a variable that belongs to the TUNNEL env and that the bucket
# env does not declare. The wrapper was refusing to apply an env
# because of a value that env has no use for.
#
# The subject is each env's own `variables.tf`, and variables WITH a
# default are skipped: a default is the declaration that the value is
# optional, and demanding it would contradict the file that declares
# it.
#
# The -chdir is parsed here and not only further down, because the
# guard needs to know which env it is guarding. If it cannot be
# derived, the historical list is kept and SAID: a guard that silently
# stops guarding is worse than one that guards too much.
_ENV_FOR_GUARD=""
for _a in "$@"; do case "$_a" in -chdir=*) _ENV_FOR_GUARD="${_a#-chdir=}" ;; esac; done
# ABSOLUTE OR RELATIVE, and this file already warned about it fifty
# lines below: an absolute -chdir turns "$HERE/$ENV" into a garbage
# path. The first version of this guard concatenated blindly, could
# not find variables.tf, and fell back to the historical list — which
# is exactly the failure it was written to fix. It was caught in one
# reading only because the fallback SAYS it is falling back.
_ENV_DIR="$_ENV_FOR_GUARD"
case "$_ENV_DIR" in /*) : ;; *) _ENV_DIR="$HERE/$_ENV_DIR" ;; esac
INJECTED=()
if [[ -n "$_ENV_FOR_GUARD" && -f "$_ENV_DIR/variables.tf" ]]; then
    while read -r _v; do
        [[ -n "$_v" ]] && INJECTED+=("TF_VAR_$_v")
    done < <(python3 - "$_ENV_DIR/variables.tf" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
for m in re.finditer(r'variable\s+"([a-z0-9_]+)"\s*\{(.*?)\n\}', src, re.S):
    if not re.search(r'^\s*default\s*=', m.group(2), re.M):
        print(m.group(1))
PY
    )
else
    log "could not derive the variables of ${_ENV_FOR_GUARD:-<no -chdir>}: keeping the historical list"
    INJECTED=(TF_VAR_cloudflare_api_token TF_VAR_cloudflare_access_token \
              TF_VAR_cloudflare_account_id \
              TF_VAR_cloudflare_zone_id TF_VAR_root_domain \
              TF_VAR_operador_email)
fi
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

# ── THE PLAINTEXT DOES NOT OUTLIVE THE CALL, however the call ends ──────
# MEASURED 2026-10-09 on the home instance: terraform.tfstate and its
# .backup had been sitting in the env since 25-09 —600, ignored by git,
# and with the tunnel's token and the Access service token's secret IN
# THE CLEAR— and one `grep` over the tofu tree printed both. The
# encrypted copy is the truth (#46) and every call decrypts it again, so
# the plaintext is a working file of THIS call and dies with it.
#
# It dies on EVERY way out, not only at the end of a call that got
# there: until 2026-10-14 the re-encrypt and the shred were the last
# lines of the script, so a TERM while tofu ran (a closed terminal, a
# unit stopped), a second Ctrl-C, or a die between the decrypt and the
# end left the state in the clear exactly as the 2026-10-09 corpse was
# found (review of 2026-10-13, A-9). Now they live in finish_state,
# which the EXIT trap runs on any exit and the INT/TERM trap runs on a
# signal: bash runs a trap only once the foreground command (tofu) has
# returned, so the state it hands over is whole. Inside the handler a
# further INT/TERM is ignored (the handler takes about a second) and the
# EXIT trap is cleared so it runs once. Check 277.
finish_state() {
    trap '' INT TERM
    trap - EXIT
    [[ -n "$PLAIN" && -f "$PLAIN" ]] || return 0
    local finish_rc=0
    # Re-encrypt ONLY if the state changed. sops produces different text on
    # every run even when the content is identical (a fresh data key), so
    # re-encrypting always would fill git with diffs that mean nothing —
    # and a diff that means nothing is a diff that stops being read.
    # A plaintext state with NO encrypted twin (an instance from before #46,
    # or a first apply) is encrypted even if this call did not change it:
    # the plaintext is about to be shredded below, and it must not be the
    # only copy when that happens.
    if [[ ! -f "$ENCRYPTED" || "$(fingerprint "$PLAIN")" != "$FINGERPRINT_BEFORE" ]]; then
        if ! command -v sops >/dev/null; then
            log "ERROR: the state changed and sops is not in PATH"
            finish_rc=1
        else
            umask 077
            # --config NAMED, not looked up. sops searches for .sops.yaml
            # upwards FROM THE CURRENT DIRECTORY, and this wrapper is called
            # from wherever the phase happens to stand — on 2026-08-31 that was
            # the product's clone, which has no .sops.yaml, so sops answered
            # «no creation rules» about a rule that was right there. Measured
            # both ways that day: from the env's directory it encrypted fine,
            # from the product's clone it did not, with the same file and the
            # same rule. A behaviour that depends on the caller's cwd is a
            # behaviour nobody can reason about from reading this file.
            if sops --config "$HERE/../.sops.yaml" \
                    -e --input-type json --output-type json \
                    --filename-override "$ENCRYPTED" "$PLAIN" > "$ENCRYPTED.tmp" \
               && mv "$ENCRYPTED.tmp" "$ENCRYPTED"; then
                log "state re-encrypted -> $(basename "$ENCRYPTED")  — COMMIT IT"
                log "  without that commit, the next recovery does not know this exists."
            else
                rm -f "$ENCRYPTED.tmp"
                log "ERROR: sops -e of the state failed (config: $HERE/../.sops.yaml)"
                finish_rc=1
            fi
        fi
    fi
    # Shredded only once the encrypted copy is PROVEN to hold the same state
    # (decrypted and compared as JSON, never shown): a state that cannot be
    # proven is left in place, loudly — losing it would be worse than
    # leaving it. tofu's own .backup and the `state rm` backups go too: they
    # are the previous state, and git already has that, encrypted.
    if [[ -f "$ENCRYPTED" ]] && sops -d --output-type json "$ENCRYPTED" 2>/dev/null \
         | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin) == json.load(open(sys.argv[1])) else 1)' \
             "$PLAIN" 2>/dev/null; then
        shred -u "$PLAIN"
        [[ -f "$PLAIN.backup" ]] && shred -u "$PLAIN.backup"
        find "$(dirname "$PLAIN")" -maxdepth 1 -name 'terraform.tfstate.*.backup' -exec shred -u {} +
        log "plaintext state shredded — the encrypted copy holds the same state"
    else
        log "WARNING: the plaintext state was LEFT in $(dirname "$PLAIN"): the encrypted copy"
        log "  could not be proven to hold the same state (no age key to decrypt it, or they differ)."
        log "  It holds the tunnel's secrets in the clear: re-run with SOPS_AGE_KEY_FILE exported."
    fi
    (( finish_rc == 0 )) || exit 1
}
trap finish_state EXIT
trap 'finish_state; exit 130' INT TERM


# `tofu` and not `exec tofu`: we have to come back AFTERWARDS to
# re-encrypt. stdout still passes straight through —the callers capture
# `output -raw tunnel_id` with $()— because nothing is redirected here.
log "TF_VARs injected (${#INJECTED[@]}). Delegating to tofu: $*"

# ── what tofu PRINTS about a plan is not shown with its values ──────────
# MEASURED 2026-09-30 on alpha-arch: `aegis destroy` without --yes printed
# the tunnel's secret. The hashicorp/random provider does not mark
# random_id's values as sensitive, so `plan -destroy` shows
# `b64_std = "…" -> null` — and a random_id's ID is the secret itself, so
# every `Creation complete … [id=…]` of phase 25's apply wrote it into the
# install log too. Changing the resource type would recreate the tunnel on
# every live instance; the class is «tofu prints state values», and this
# wrapper is the one door every tofu call goes through (A14). So for
# plan / apply / destroy what tofu prints goes through a filter: the
# resource addresses, the actions, the summary and the errors stay; every
# attribute's VALUE and every `[id=…]` become «(not shown)». `output` and
# the rest are untouched (stdout is sacred: phase 25 captures
# `output -raw`). To see the values by hand while debugging:
# AEGIS_TOFU_SHOW_VALUES=1 — explicit, never a default.
#
# TOFU COLOURS WHAT IT PRINTS EVEN INTO A PIPE (measured 2026-10-02,
# OpenTofu 1.12.6: `+ input = "…"` arrives as `ESC[32m+ESC[0m input = "…"`),
# and the first version of this filter, which matched plain lines, let the
# value through — its check passed against a fake tofu that printed no
# colour. So `-no-color` is put right after the subcommand (not at the end:
# after a positional plan file it would be read as a second positional),
# and the filter strips whatever escape codes still arrive before it looks.
#
# python3 AND NOT awk (this wrapper already needs python3 twice above):
# mawk — the awk of Ubuntu and Debian — holds a pipe's input until a block
# fills, so a minute-long apply would print nothing and then everything;
# and tofu's prompt («Enter a value: ») ends without a newline, which a
# line filter never lets out: an apply by hand would sit mute, waiting for
# an answer to a question nobody saw. This one writes each line as it
# arrives and lets the prompt through.
_SUB=""
for _a in "$@"; do case "$_a" in -*) ;; *) _SUB="$_a"; break ;; esac; done
_REDACT_PY='
import os, re, sys
ansi = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]")
attr = re.compile(rb"^(\s*(?:[-+~]|-/\+|\+/-)?\s*\"?[A-Za-z0-9_.-]+\"?\s+=\s)")
ident = re.compile(rb"\[id=[^\]]*\]")
out = sys.stdout.buffer
heredoc = False
def line(raw):
    global heredoc
    s = ansi.sub(b"", raw)
    if heredoc:
        if s.strip() == b"EOT":
            heredoc = False
            return s
        return None
    s = ident.sub(b"[id=(not shown)]", s)
    m = attr.match(s)
    if m:
        if re.search(rb"<<-?EOT\s*$", s):
            heredoc = True
        return m.group(1) + b"(not shown)"
    return s
pending = b""
while True:
    chunk = os.read(0, 65536)
    if not chunk:
        break
    pending += chunk
    parts = pending.split(b"\n")
    pending = parts.pop()
    for p in parts:
        r = line(p)
        if r is not None:
            out.write(r + b"\n")
    if ansi.sub(b"", pending).rstrip().endswith(b"Enter a value:"):
        out.write(ansi.sub(b"", pending))
        pending = b""
    out.flush()
if pending:
    r = line(pending)
    if r is not None:
        out.write(r)
out.flush()
'
set +e
if [[ "${AEGIS_TOFU_SHOW_VALUES:-0}" != 1 && "$_SUB" =~ ^(plan|apply|destroy)$ ]]; then
    _ARGS=() ; _PLACED=0
    for _a in "$@"; do
        _ARGS+=("$_a")
        if [[ $_PLACED -eq 0 && "$_a" == "$_SUB" ]]; then _ARGS+=(-no-color); _PLACED=1; fi
    done
    # ONE FILTER PER STREAM: tofu's errors stay on stderr. Merged into
    # stdout (as the first version did), a caller that silences stdout
    # lost the errors with it. Both filters are pipeline members, so both
    # have flushed when this line returns; tofu's exit code comes back
    # through a file because its group runs in a subshell.
    _RCF="$(mktemp)"
    { { tofu "${_ARGS[@]}"; echo $? > "$_RCF"; } 2>&1 1>&3 3>&- \
        | python3 -u -c "$_REDACT_PY" >&2; } 3>&1 \
        | python3 -u -c "$_REDACT_PY"
    RC="$(cat "$_RCF" 2>/dev/null)"; rm -f "$_RCF"
    [[ "$RC" =~ ^[0-9]+$ ]] || RC=1
else
    tofu "$@"
    RC=$?
fi
set -e

exit $RC
