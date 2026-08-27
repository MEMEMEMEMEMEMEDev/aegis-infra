#!/usr/bin/env bash
# PHASE 00 — preflight: preconditions and known limits.
# The init contract is explicit: if a precondition is not met, we
# ABORT HERE, not in phase 40 with half a cluster already built.
# (27 §2.4: the H4/H5 limits become a verified preflight.)
set -euo pipefail

log_info "Preflight — profile: $PROFILE"

# ── known v1 limits (ALWAYS shown) ──────────────────────────────────
cat <<'EOF'
KNOWN LIMITS OF THIS INIT (v1):
 - Does NOT cover total loss of GitHub (bootstrap starts with a clone).
 - Does NOT import live Cloudflare/GitHub resources: the greenfield
   profile RECREATES (new tunnel => new token). The re-bootstrap
   profile with import does NOT exist yet.
 - The Windows side (WSL2/.wslconfig) is VERIFIED and GUIDED, not
   configured automatically.
EOF

# ── hard preconditions ──────────────────────────────────────────────
# 1. Config: GUIDED. No conf → the wizard asks field by field
#    (explanation + default + validation) and writes it; with a valid
#    conf → it goes straight through (re-runs). The operator answers
#    questions, they do not edit files (operator's mission; same
#    principle as the secrets: generate+guide).
ensure_config    # defines and validates every var (lib/config.sh)

# 1a. The instance's platform/ exists from HERE on: this phase's
#     host-key gate and phase 05's pins read it, and on a clean
#     machine (product != instance) nothing had created it yet.
#     Idempotent; never touches an instance that already has .git.
seed_platform_dir

# 1b. host/network DOCTOR (P0.4/P0.5 audit 2026-07-18): EVERYTHING
#     that killed phases 30-40 minutes into real runs is verified
#     HERE, with the remediation in the message. The doctor diagnoses
#     and guides; it does not reconfigure the host on its own.
# H3 run #15: jq stopped phase 00 on a clean VM (a prerequisite
# neither documented nor installed — phase 05 installs it AFTER
# phase 00 demands it). If sudo NOPASSWD is available, we install it
# HERE, logged; if not, the gate below stops with the exact command
# (as in #15):
if ! command -v jq >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    log_warn "jq missing — installing it (sudo NOPASSWD available; H3 #15)"
    retry_net 3 sudo apt-get -o DPkg::Lock::Timeout=600 install -y jq || \
        log_warn "could not install jq on my own — the gate below carries the manual command"
fi
gate "bootstrap-bins" check_bootstrap_bins
gate "dev-shm" check_dev_shm
gate "egress-ipv6" check_ipv6_trap
gate "dns-efectivo" check_egress_dns
# H1 run #15: the clock's verdict is the REAL SKEW against an
# external source (hard gate); timedatectl stays informational only:
gate "reloj-sin-skew" check_clock_skew
check_clock_ntp   # informational (weak signal with chrony — H1)
# ── the zone's NS: a question that belongs to CLOUDFLARE ────────────
# With EDGE=cloudflare the whole edge lives inside a zone of YOURS:
# phase 25 writes the tunnel's CNAMEs there and Access publishes its
# app there. A domain whose NS point somewhere else does not fail
# here — it fails THERE, half a cluster in, which is the very thing
# this preflight exists to prevent.
# With EDGE=local there is no zone at all: ROOT_DOMAIN is a NAME FOR
# AN ADDRESS (sslip.io, or a line in /etc/hosts), delegated by nobody
# and owned by nobody, so "do its NS point at Cloudflare" has no
# subject — asking 1.1.1.1 for the NS of 127-0-0-1.sslip.io answers
# about sslip.io's zone, which is somebody else's, not about this
# instance. What is LOST with local is that early warning about the
# delegation; there is nothing to warn about because there is nothing
# delegated.
# What DOES apply under local is the other half of the same worry,
# and nothing else in the init covers it: that the name RESOLVES from
# this host, and that it resolves to the address the bridge is going
# to listen on. sslip.io needs egress to answer, and a machine with
# no way out resolves nothing: the cluster comes up perfectly healthy
# and every URL of the platform is a dead end. Cheap to see here,
# expensive to discover in phase 90.
if [[ "${EDGE:-cloudflare}" == local ]]; then
    # Through gate_no_subject and not a bare log_warn: the human log is
    # not the channel that survives. A gate that only says it in prose
    # leaves gates.jsonl with NOTHING, and a line that is missing there
    # reads exactly like one that passed.
    gate_no_subject "ns-en-cloudflare" \
      "EDGE=local: there is no zone of yours to delegate. $ROOT_DOMAIN is a name for an address (sslip.io / /etc/hosts), no nameserver of yours answers for it, and there is no tunnel or Access in front. The delegation cannot be checked because there is no delegation; what is gated in its place is that the name resolves HERE (edge-name-resolves)"
    # getent = the system's EFFECTIVE resolver, the same criterion as
    # check_egress_dns: what the browser and the kubelet will see, not
    # what an arbitrary server answers. ahostsv4 because EDGE_BIND_IP
    # is IPv4 by validation. The root AND one subdomain, because
    # sslip.io answers for every label but /etc/hosts HAS NO WILDCARD,
    # and the trap of the by-hand remedy is exactly a root that
    # resolves with an argocd. that does not.
    _edge_name_resolves() {
        local host addrs dead=() elsewhere=()
        for host in "$ROOT_DOMAIN" "argocd.$ROOT_DOMAIN"; do
            # No 2>/dev/null: retry_net's notices go to stderr (every
            # log_* does) and only stdout is captured, so the wait is
            # never mute — the same as check_egress_dns.
            addrs="$(retry_net 3 bash -c "getent ahostsv4 '$host'" \
                     | awk '{print $1}' | sort -u | tr '\n' ' ')" || addrs=""
            if [[ -z "${addrs// /}" ]]; then dead+=("$host"); continue; fi
            grep -qFw -- "$EDGE_BIND_IP" <<< "$addrs" || elsewhere+=("$host -> ${addrs% }")
        done
        if ((${#dead[@]})); then
            log_error "does NOT resolve on this host: ${dead[*]} — with EDGE=local nobody publishes this name for you. Remedy: an sslip.io name (<ip-with-dashes>.sslip.io resolves to that IP with no zone and no configuration, as long as this machine reaches the Internet), or your own resolver answering the wildcard (dnsmasq: address=/$ROOT_DOMAIN/$EDGE_BIND_IP). /etc/hosts also works, but it HAS NO WILDCARD: the line must name every host, '$EDGE_BIND_IP $ROOT_DOMAIN argocd.$ROOT_DOMAIN jenkins.$ROOT_DOMAIN grafana.$ROOT_DOMAIN ntfy.$ROOT_DOMAIN aegis.$ROOT_DOMAIN'"
            return 1
        fi
        # WHICH address it resolves to is a separate verdict, and a
        # WEAK one: with EDGE_BIND_IP=0.0.0.0 the bridge answers on
        # every address of the host and the comparison has no subject,
        # so it is stated as NOT EVALUATED and never as a pass. A
        # mismatch is a warning and not a failure for the same reason
        # check_domain_on_cloudflare only fails on positive evidence:
        # a host with several addresses can be legitimately reachable
        # by an address that is not this one.
        if [[ "$EDGE_BIND_IP" == 0.0.0.0 ]]; then
            log_warn "resolution OK, but WHICH address it resolves to was NOT EVALUATED: EDGE_BIND_IP=0.0.0.0 means the bridge answers on every address of the host, so there is no single address to compare against (this is a notice, not an approval)"
        elif ((${#elsewhere[@]})); then
            log_warn "resolves to an address that is NOT the bridge's ($EDGE_BIND_IP): ${elsewhere[*]} — the URLs of the platform will land somewhere else unless that address also reaches this host"
        else
            log_ok "$ROOT_DOMAIN and argocd.$ROOT_DOMAIN resolve to $EDGE_BIND_IP (the bridge's address)"
            return 0
        fi
        log_ok "$ROOT_DOMAIN and argocd.$ROOT_DOMAIN resolve from this host (the address they resolve to is in the notice above)"
    }
    gate "edge-name-resolves" _edge_name_resolves
else
    gate "ns-en-cloudflare" check_domain_on_cloudflare "$ROOT_DOMAIN"
fi

# 1c. sudo EARLY (P0.4): with neither NOPASSWD nor an operator, the
#     run died in phase 20 (~30 min). -K purges the cache (the false
#     positive of run #5). Interactively it only warns (phase 20 will
#     ask for the password ONCE); unattended it is hard:
sudo -K 2>/dev/null || log_info "(no sudo cache to purge)"
if sudo -n true 2>/dev/null; then
    log_ok "sudo NOPASSWD active — phases 20/40 run without a prompt"
elif ni_mode; then
    die "sudo without NOPASSWD under --non-interactive — install it BEFORE: printf '%s ALL=(ALL) NOPASSWD:ALL\n' \"\$(id -un)\" | sudo tee /etc/sudoers.d/010-aegis-init-nopasswd && sudo chmod 0440 /etc/sudoers.d/010-aegis-init-nopasswd"
else
    log_warn "sudo will ask for a password in phase 20 (or install NOPASSWD now so you don't have to be present: drop-in in /etc/sudoers.d)"
fi

# 2. Supported host (designed on Ubuntu 24.04; 26.04 tolerated with
#    a warning — the checks are version-agnostic, but the fact stays
#    in plain sight in case something odd shows up later):
gate "wsl2-o-linux" check_wsl2
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    log_info "OS detected: ${PRETTY_NAME:-unknown}"
    case "${VERSION_ID:-}" in
        24.04|26.04) ;;
        *) log_warn "Ubuntu ${VERSION_ID:-?} is not on the tested list (24.04/26.04)" ;;
    esac
fi

# 3. gh is an operator PREREQUISITE (installed + authenticated
#    BEFORE init): it is THE GitHub credential for the whole flow
#    (D10 — it creates repos, settings, webhooks; there is no PAT).
#    If it is missing:
#    apt install gh && gh auth login  (scopes: repo + repo admin)
gate "github-auth" check_github_reachable

# 3b. GitHub's pinned host keys are still current (A32 — detects a
#     GitHub rotation BEFORE baking the values into the cluster):
gate "github-hostkeys-vigentes" check_github_hostkeys_pin

# 4. Disk space (registry+jenkins+trivy PVCs; threshold 20G):
gate "disco-20G" bash -c \
    '[[ $(df --output=avail -BG / | tail -1 | tr -dc 0-9) -ge 20 ]]'

# 5. Greenfield on a host with a previous kubeconfig: confirm that
#    nothing live is being stepped on (A11 inverted: here the danger
#    is TRAMPLING).
if kubectl config current-context >/dev/null 2>&1; then
    log_warn "active kubeconfig: $(kubectl config current-context)"
    gate_red "greenfield with an existing kubeconfig — confirm that cluster does NOT matter"
fi

# 6. safekeeping by hand (agnostic — init assumes no password manager):
human_step "Safekeeping ready" \
  "Phase 10 will show you the age key ONCE so you can store it" \
  "wherever you keep your secrets (manager, paper, USB stick)." \
  "It is THE ONLY value you will store by hand in the whole init" \
  "(everything else is persisted encrypted and recovered with that key)." \
  "Have your safekeeping place reachable NOW."

log_ok "Preflight complete — limits accepted, preconditions OK"
