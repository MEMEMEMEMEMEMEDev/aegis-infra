#!/usr/bin/env bash
# aegis-init lib/checks.sh — preflight and environment checks.
# All of them READ-ONLY. Every check returns 0/1 and logs evidence
# (gates demand evidence, not "looks like it").

set -euo pipefail

# ── binaries ────────────────────────────────────────────────────────
# Userland pins in platform/ansible/inventory/group_vars/all.yml
# (A12: literal pins). check_binaries does not install — phase 05 does.
REQUIRED_BINS=(tofu sops age age-keygen kubectl helm jq direnv gh \
               python3 git openssl htpasswd ssh-keygen rsync cosign)

check_binaries() {
    local missing=() b
    for b in "${REQUIRED_BINS[@]}"; do
        command -v "$b" >/dev/null || missing+=("$b")
    done
    if ((${#missing[@]})); then
        log_warn "missing binaries: ${missing[*]}"
        return 1
    fi
    log_ok "userland complete (${#REQUIRED_BINS[@]} binaries)"
}

# yq is deliberately NOT required: the host convention is python3+pyyaml
# (rule C7); yq only inside pods.

# ── kubeconfig / cluster target ─────────────────────────────────────
# A11: the someone-else's-kubeconfig pothole almost deployed the tunnel
# on another project's infra. POSITIVE verification of the target, always.
check_kube_context() {
    local expected="$1"
    local current
    current="$(kubectl config current-context 2>/dev/null || echo NONE)"
    if [[ "$current" != "$expected" ]]; then
        log_error "current-context='$current', expected '$expected'"
        return 1
    fi
    kubectl get nodes -o name >/dev/null || return 1
    log_ok "kubeconfig points at '$expected' and answers"
}

check_default_storageclass() {
    # 1.2c: without a default SC the PVCs sit Pending with no clear error.
    kubectl get storageclass -o json | python3 -c '
import sys, json
scs = json.load(sys.stdin)["items"]
d = [s["metadata"]["name"] for s in scs
     if s["metadata"].get("annotations", {}).get(
        "storageclass.kubernetes.io/is-default-class") == "true"]
sys.exit(0 if d else 1)'
}

# ── WSL2 / the Windows side (verified checklist, not automated) ─────
check_wsl2() {
    grep -qi microsoft /proc/version || {
        log_info "not WSL2 (hetzner profile: OK)"; return 0; }
    local issues=()
    # systemd active:
    [[ "$(ps -p 1 -o comm=)" == "systemd" ]] || issues+=("systemd is not PID 1 (wsl.conf [boot] systemd=true)")
    # mirrored networking (best effort: the signal is the shared IP):
    # CORNER-CASE NOTE: there is no clean API to read .wslconfig from
    # the inside; this VERIFIES symptoms and GUIDES, it does not
    # configure (27 §3.3).
    if ((${#issues[@]})); then
        printf '  - %s\n' "${issues[@]}"
        return 1
    fi
    log_ok "WSL2: systemd OK (check .wslconfig by hand if in doubt about RAM/networking)"
}

# ── account preconditions (known limits H4/H5) ──────────────────────
check_github_reachable() {
    retry_net 3 gh auth status >/dev/null 2>&1
}
check_repo_clean_main() {
    local repo="$1"
    git -C "$repo" fetch origin main --quiet || return 1
    [[ -z "$(git -C "$repo" status --porcelain)" ]] || {
        log_warn "repo $repo has local changes"; return 1; }
}

# ── age / SOPS ──────────────────────────────────────────────────────
check_age_key_operational() {
    # A2: the explicit var, do not trust direnv in non-interactive.
    [[ -n "${SOPS_AGE_KEY_FILE:-}" ]] || {
        log_error "SOPS_AGE_KEY_FILE not exported"; return 1; }
    [[ -f "$SOPS_AGE_KEY_FILE" ]] || {
        log_error "$SOPS_AGE_KEY_FILE does not exist"; return 1; }
    [[ "$(stat -c %a "$SOPS_AGE_KEY_FILE")" == "600" ]] || {
        log_warn "permissions != 600 on the age key"; return 1; }
    log_ok "age key operational at \$SOPS_AGE_KEY_FILE (600)"
}

check_sops_roundtrip() {
    # a real roundtrip against a file in the repo (prints no values).
    # sops_env: re-derives SOPS_AGE_KEY_FILE at the point of use (bug 5
    # of validation #3 — the gates run in subshells and the export
    # along the --from path had holes):
    local encfile="$1"
    sops_env
    sops -d "$encfile" | head -c1 >/dev/null
}

# ── GitHub host keys (pin vs official source) ───────────────────────
# The host keys are PINNED in jenkins/values.yaml (declarative T1,
# taken from api.github.com/meta on 2026-07-06). This check detects a
# GitHub rotation: every pinned key must still be in /meta. A failure =
# update the values BEFORE bootstrapping (A32: official source).
check_github_hostkeys_pin() {
    local values="$PLATFORM_DIR/k8s/base/platform/jenkins/values.yaml"
    local meta
    meta="$(mktemp)"
    # gh api (AUTHENTICATED, 5000 req/h) and not anonymous curl (60/h):
    # in iterative validation sessions the anonymous rate limit made
    # the gate fail with a misleading "(network?)" (bug 2 of
    # validation #3). gh is already guaranteed: the github-auth gate
    # runs first.
    if ! retry_net 3 bash -c "gh api meta > '$meta'"; then
        log_error "gh api meta failed — if the error above says 'rate limit' it is NOT the network; if it is timeout/DNS, check the network first"
        rm -f "$meta"; return 1
    fi
    python3 - "$values" "$meta" <<'EOF'
import json, re, sys
values, meta = open(sys.argv[1]).read(), json.load(open(sys.argv[2]))
official = set(k.split()[1] for k in meta["ssh_keys"])
pinned = set(re.findall(r'github\.com\s+\S+\s+(AAAA\S+)', values))
stale = pinned - official
if stale:
    print("pinned host keys that are NO LONGER in /meta:", file=sys.stderr)
    for k in sorted(stale):
        print(f"  {k[:24]}...", file=sys.stderr)
    sys.exit(1)
sys.exit(0 if pinned else 1)
EOF
    local rc=$?
    rm -f "$meta"
    (( rc == 0 )) && log_ok "pinned host keys still current according to api.github.com/meta"
    return "$rc"
}

# ── network / DNS (preflight doctor — P0.5 audit 2026-07-18) ────────
# Phase 00 checked NOTHING of what actually killed runs (broken IPv6,
# per-NIC DNS pointing at a dead resolver, a clock with no NTP) — the
# failures showed up 30-40 min in, with 4+ phases of state written, and
# the operator fixed them BY HAND in the real run. The doctor verifies
# AND gives the exact remediation; it does not configure by itself.

# binaries the preflight/wizard ITSELF needs (before phase 05 installs
# the userland): without this, phase 00 died with a cryptic "command
# not found" instead of an actionable list:
check_bootstrap_bins() {
    local missing=() b
    for b in python3 curl git sudo jq; do
        command -v "$b" >/dev/null || missing+=("$b")
    done
    python3 -c 'import yaml' 2>/dev/null || missing+=("python3-yaml")
    if ((${#missing[@]})); then
        log_error "missing for the preflight: ${missing[*]} — 'sudo apt install ${missing[*]}'"
        return 1
    fi
    log_ok "bootstrap binaries present (python3+yaml, curl, git, sudo, jq)"
}

# REAL resolution of the hosts the init consumes (getent = the system's
# effective resolver, not an arbitrary DNS):
check_egress_dns() {
    local h bad=()
    for h in github.com api.cloudflare.com get.k3s.io docker.io; do
        retry_net 3 bash -c "getent ahosts '$h' >/dev/null" || bad+=("$h")
    done
    if ((${#bad[@]})); then
        log_error "do not resolve: ${bad[*]} — check the PER-INTERFACE resolver ('resolvectl status'): in the real run the host-only NIC pointed at a dead DNS and the global one covered the hole now and then"
        return 1
    fi
    log_ok "the effective DNS resolves github/cloudflare/k3s/docker"
}

# IPv6 trap (fixed BY HAND in the real run): the host advertises IPv6
# but the v6 path is broken → curls that hang/fail depending on which
# family happy-eyeballs falls into. Signal: v4 works and dual fails:
check_ipv6_trap() {
    if curl -fsS -m 15 -o /dev/null https://api.github.com/meta 2>/dev/null; then
        log_ok "https egress OK (dual-stack)"
        return 0
    fi
    if curl -4 -fsS -m 15 -o /dev/null https://api.github.com/meta 2>/dev/null; then
        log_error "egress FAILS dual-stack but WORKS forced to IPv4 — broken IPv6 path (the trap from the real run). Remediation: sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1 (persist it in /etc/sysctl.d/) or fix the v6 route"
        return 1
    fi
    log_error "https egress does not work over IPv4 either — network down? (retry once it settles)"
    return 1
}

# clock — H1 run #15: the VM booted ~9h20m BEHIND with NTP "active".
# timedatectl is NOT a trustworthy signal with chrony installed (it
# reads systemd's flag, not chrony — it lies in BOTH directions), and
# chrony corrects by slew: a big jump would take weeks. The REAL signal
# is the skew against an external source the init ALREADY consumes: the
# Date header of api.github.com. |skew|>60s = RED with remediation (a
# clock that has drifted makes freshly issued certs/tokens look
# not-yet-valid — cryptic failures 5 phases later):
check_clock_skew() {
    local hdr remote_ts local_ts skew
    hdr="$(retry_net 3 bash -c \
        "curl -fsSI -m 15 https://api.github.com/meta 2>/dev/null \
         | tr -d '\r' | awk 'tolower(\$1)==\"date:\"{ \$1=\"\"; print substr(\$0,2); exit }'")" \
        || { log_warn "could not read the Date header of api.github.com — clock skew INCONCLUSIVE (network)"; return 0; }
    [[ -n "$hdr" ]] || { log_warn "response with no Date header — skew inconclusive"; return 0; }
    remote_ts="$(date -ud "$hdr" +%s 2>/dev/null)" || \
        { log_warn "could not parse the remote Date ('$hdr') — skew inconclusive"; return 0; }
    local_ts="$(date -u +%s)"
    skew=$(( local_ts - remote_ts ))
    if (( skew > 60 || skew < -60 )); then
        log_error "CLOCK OUT OF SYNC: skew ${skew}s against api.github.com (local $(date -u +%FT%TZ)). Remediation: with chrony 'sudo chronyc makestep'; with timesyncd 'sudo timedatectl set-ntp true && sudo systemctl restart systemd-timesyncd'. Verify by re-running this phase. WATCH OUT: 'timedatectl … synchronized' is NOT trustworthy with chrony"
        return 1
    fi
    log_ok "clock OK (skew ${skew}s vs api.github.com)"
}

# residual informational (NOT a gate — H1: the signal is weak by design):
check_clock_ntp() {
    local sync
    sync="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"
    log_info "timedatectl NTPSynchronized=$sync (WEAK signal — the real verdict is the skew gate)"
    return 0
}

# secrets tmpfs available (secrets_workdir assumes it):
check_dev_shm() {
    local t
    t="$(mktemp -d /dev/shm/aegis-preflight.XXXXXX 2>/dev/null)" || {
        log_error "/dev/shm not writable — secret handling (tmpfs+shred) cannot operate"
        return 1; }
    rmdir "$t"
    log_ok "/dev/shm operational (secrets tmpfs)"
}

check_domain_on_cloudflare() {
    # 0.6: the domain's NS pointing at Cloudflare. The old check was a
    # NO-OP (unconditional sys.exit(0) — audit 2026-07-18): it went
    # green with any domain and the real error blew up in phase 25
    # (tofu) or 35 (public DNS). With no dig guaranteed on the host:
    # DNS-over-HTTPS against 1.1.1.1 (curl+jq already required).
    # FAIL only on positive evidence of someone else's NS; with no
    # conclusive answer (odd network) it stays WARN — the hard check
    # against the CF API is still in phase 25:
    local domain="$1" ns_json ns_list
    ns_json="$(retry_net 3 curl -fsS -m 15 \
        -H 'accept: application/dns-json' \
        "https://1.1.1.1/dns-query?name=${domain}&type=NS" 2>/dev/null)" || {
        log_warn "could not query the NS of $domain (DoH 1.1.1.1) — inconclusive; phase 25 validates it the hard way via API"
        return 0; }
    ns_list="$(jq -r '.Answer[]?.data // empty' <<< "$ns_json" | tr -d ' ')"
    if [[ -z "$ns_list" ]]; then
        log_warn "no NS records visible for $domain — a freshly created zone? phase 25 validates it the hard way via API"
        return 0
    fi
    if grep -qi 'ns\.cloudflare\.com' <<< "$ns_list"; then
        log_ok "the NS of $domain point at Cloudflare"
        return 0
    fi
    printf '%s\n' "$ns_list" >&2
    log_error "the NS of $domain are NOT Cloudflare's (above) — the zone must be active in your CF account BEFORE the init"
    return 1
}
