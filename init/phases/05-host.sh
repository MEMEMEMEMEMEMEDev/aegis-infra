#!/usr/bin/env bash
# PHASE 05 — host: installs the PINNED Linux userland, verifies the
# Windows side (actionable checklist, not automation — 27 §3.3).
# Settles H-1: the old bootstrap only VERIFIED binaries; this one
# installs them (the install-cli-tools.yml the overview named and that
# never existed — overview.md:283).
set -euo pipefail

# ── userland pins (A12: literals, not channels) ─────────────────────
# The source of truth for versions is group_vars/all.yml in the
# platform repo; we read them here so as not to duplicate:
PINS_FILE="$PLATFORM_DIR/ansible/inventory/group_vars/all.yml"
gate "pins-presentes" test -f "$PINS_FILE"

read_pin() {  # python3+pyyaml, NOT yq (rule C7)
    # missing key = CLEAN FAILURE, not a traceback (H1 validation #1:
    # git/openssl were missing and the raw KeyError hid the hole — a
    # silent fallback is worse than an explicit failure):
    python3 -c "
import sys, yaml
pins = yaml.safe_load(open('$PINS_FILE'))['userland_pins']
if '$1' not in pins:
    sys.exit(3)
print(pins['$1'])" || die "missing pin in userland_pins for '$1' \
(add it to group_vars/all.yml — 'apt' if apt manages it)"
}

# ── apt with lock wait (bug run #10) ────────────────────────────────
# On a VM's first boot, unattended-upgrades holds the dpkg lock →
# "could not get lock" and the userland was left half-done (htpasswd
# and rsync did not get installed; the userland-completo gate caught
# the hole). apt has a NATIVE wait: DPkg::Lock::Timeout blocks for up
# to N seconds waiting for the lock instead of failing. EVERY apt-get
# in this phase goes through here (including the local sops .deb — apt
# installs local paths, dpkg -i does not wait for locks).
apt_locked() { sudo apt-get -o DPkg::Lock::Timeout=600 "$@"; }

# ── per-tool installation (idempotent: if present and the pin
#    matches, skip; if present with ANOTHER version, warn and do NOT
#    overwrite without a RED) ───────────────────────────────────────
# tool_version: the first x.y[.z] string the binary emits. Every tool
# prints its version differently; the regex is the common minimum.
tool_version() {
    local tool="$1"
    case "$tool" in
        kubectl) kubectl version --client 2>/dev/null ;;
        *)       "$tool" --version 2>/dev/null || "$tool" version 2>/dev/null ;;
    esac | grep -om1 '[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?' || echo unknown
}

install_tool() {
    local tool="$1" pin ver
    pin="$(read_pin "$tool")"
    if command -v "$tool" >/dev/null; then
        # pin "apt" = NO hard pin: presence is enough, there is no
        # version to compare (H2 validation #1: comparing the real
        # version against the literal "apt" gave a false drift → RED
        # on gh, which is besides an authenticated operator
        # PREREQUISITE — phase 00 demands it before this one runs):
        if [[ "$pin" == "apt" ]]; then
            log_info "$tool present (apt-managed, no hard pin)"
            return 0
        fi
        ver="$(tool_version "$tool")"
        if [[ "$ver" == "$pin"* ]]; then
            log_info "$tool $ver already present == pin $pin"
        else
            # drift: it is NOT overwritten on its own (it may be a
            # deliberate choice of the host); we warn and the operator
            # decides (A12: the pin rules in pure greenfield; on a host
            # with history, human judgement).
            log_warn "$tool DRIFT: installed $ver, pin $pin"
            gate_red "continue with $tool $ver (≠ pin $pin) — or abort and align the pin/host"
        fi
        return 0
    fi
    # P1.10 audit 2026-07-18: (a) EVERY download with retry_net — they
    # were single-attempt against the mobile network; (b) tofu was
    # installing LATEST via curl|bash (the pin was read and NOT used —
    # a non-reproducible run): now it goes through the VERSIONED .deb
    # from releases, the same pattern as sops. Per-artifact sha256
    # checksums: deferred (it requires maintaining per-version hashes
    # in group_vars — noted in VALIDACION §4; the .debs go through apt,
    # which validates their structure).
    case "$tool" in
        tofu)   run_cmd retry_net 3 bash -c "curl -fsSLo /tmp/tofu.deb https://github.com/opentofu/opentofu/releases/download/v${pin}/tofu_${pin}_amd64.deb && sudo apt-get -o DPkg::Lock::Timeout=600 install -y /tmp/tofu.deb" ;;
        sops)   run_cmd retry_net 3 bash -c "curl -fsSLo /tmp/sops.deb https://github.com/getsops/sops/releases/download/v${pin}/sops_${pin}_amd64.deb && sudo apt-get -o DPkg::Lock::Timeout=600 install -y /tmp/sops.deb" ;;
        age)    run_cmd retry_net 3 apt_locked install -y age ;;
        kubectl) run_cmd retry_net 3 bash -c "curl -fsSLo /tmp/kubectl https://dl.k8s.io/release/v${pin}/bin/linux/amd64/kubectl && sudo install -m755 /tmp/kubectl /usr/local/bin/" ;;
        helm)   run_cmd retry_net 3 bash -c "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION=v${pin} bash" ;;
        cosign) run_cmd retry_net 3 bash -c "curl -fsSLo /tmp/cosign https://github.com/sigstore/cosign/releases/download/v${pin}/cosign-linux-amd64 && sudo install -m755 /tmp/cosign /usr/local/bin/cosign" ;;
        gh)     run_cmd retry_net 3 apt_locked install -y gh ;;
        direnv) run_cmd retry_net 3 apt_locked install -y direnv ;;
        *)      run_cmd retry_net 3 apt_locked install -y "$tool" ;;
    esac
    # REAL post-install verification (real capability, not a proxy):
    gate "instalado-$tool" command -v "$tool"
}

log_info "Installing the pinned userland…"
run_cmd retry_net 3 apt_locked update -qq
# apt deps BEFORE the loop (P0.5 audit): read_pin uses pyyaml —
# installing it AFTER the loop was a race against Ubuntu minimal
# (without python3-yaml preinstalled, the first read_pin died with a
# misleading "missing pin" die). htpasswd is in apache2-utils;
# python3-venv for phase 20's ansible venv (bug 3 validation #3:
# Ubuntu minimal does not ship ensurepip):
run_cmd retry_net 3 apt_locked install -y \
    apache2-utils python3-yaml python3-venv rsync
for t in jq git openssl direnv gh age sops tofu kubectl helm cosign; do
    install_tool "$t"
done
gate "userland-completo" check_binaries

# ── the product on the PATH (03 §7) ─────────────────────────────────
# `aegis` as a command: a symlink to THIS product, so every "Resume:"
# line the init prints and every protocol that says `aegis <x>` works
# from any directory. A symlink and not a copy: the product is a repo,
# and a copy would be a second version nobody updates; every entry
# point resolves it with readlink -f. Until 2026-08-27 two comments
# (libexec/aegis-init, libexec/aegis-destroy) said this phase did it
# and nothing did — the first "Resume:" line the VPS printed was
# followed by `aegis: command not found`.
run_cmd sudo ln -sfn "$AEGIS_ROOT/bin/aegis" /usr/local/bin/aegis
gate "aegis-en-path" bash -c \
    "[[ \"\$(readlink -f \"\$(command -v aegis)\")\" == '$AEGIS_ROOT/bin/aegis' ]]"

# ── defensive direnv hook (A3) ──────────────────────────────────────
if ! grep -q 'direnv hook bash' ~/.bashrc 2>/dev/null; then
    run_cmd bash -c \
      'echo '\''command -v direnv >/dev/null && eval "$(direnv hook bash)"'\'' >> ~/.bashrc'
    log_ok "direnv hook added to .bashrc (defensive)"
fi

# ── Windows side: verified checklist (NOT automated) ───────────────
if grep -qi microsoft /proc/version; then
    human_step "Windows-side checklist (.wslconfig)" \
      "In %UserProfile%\\.wslconfig check:" \
      "  [wsl2]" \
      "  networkingMode=mirrored   (required by the stack)" \
      "  memory=  (a sane cap; the host has to live too)" \
      "And that the ext4.vhdx sits on the NVMe." \
      "If you changed anything: 'wsl --shutdown' and come back in" \
      "(this init resumes with --from 05-host)."
    gate "wsl2-post-checklist" check_wsl2
fi

log_ok "Host ready: pinned userland installed and verified"
