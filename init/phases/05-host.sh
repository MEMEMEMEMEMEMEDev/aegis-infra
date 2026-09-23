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

# ── downloads that are VERIFIED, never merely fetched ───────────────
# Until 2026-09-18 every binary of this phase arrived over https and
# was installed exactly as it came down the wire; helm arrived through
# `curl | bash` of a script off the MAIN branch of its own repo, which
# is not even a pinned script. https authenticates the SERVER, not the
# ARTIFACT: a compromised mirror, a caching proxy, a release re-cut
# under the same tag and a truncated download all pass it, and the
# machine that ends up running the result is the one that holds every
# key of the instance.
#
# So every artifact this phase downloads is compared against the
# sha256 its own publisher signs off on, before anything is installed.
# The checksum file is fetched SEPARATELY from the artifact, and when
# it cannot be read the tool is NOT installed: a download nobody could
# verify is not «probably fine», it is the third outcome wearing a
# green coat. The old note that deferred this («it requires
# maintaining per-version hashes in group_vars») was answering a
# question nobody asked — the hashes do not have to live here, they
# live upstream beside the artifact and are read at install time.
#
# apt is the other half of the answer and it needs nothing from us:
# a package installed from the distribution's repository is already
# verified against the repository's signature. That is why `apt` is a
# legitimate value of a pin, and why check 211 only demands a checksum
# of what this phase downloads with its own hands.

fetch_sha256() {   # <checksums-url> <artifact-name> → the 64 hex, on stdout
    local url="$1" name="$2" body hit
    body="$(retry_net 3 curl -fsSL --max-time 60 "$url")" || return 1
    # Two shapes exist in the wild, and the second is RECOGNISED by its
    # shape rather than assumed: a file of "<sha>  <name>" lines (helm,
    # tofu, cosign, sops), and a file that is only the hash of the one
    # artifact it belongs to (dl.k8s.io publishes kubectl.sha256 that
    # way). Guessing wrong in either direction ends in "the checksum
    # does not match" about a perfectly good download.
    hit="$(tr -d '[:space:]' <<< "$body")"
    if [[ "$hit" =~ ^[0-9a-f]{64}$ ]]; then printf '%s' "$hit"; return 0; fi
    # `*name` is the binary-mode spelling of coreutils' sha256sum; both
    # forms appear depending on who generated the file.
    hit="$(awk -v n="$name" '$2 == n || $2 == "*" n { print $1; exit }' <<< "$body")"
    [[ "$hit" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s' "$hit"
}

fetch_verified() {   # <url> <dest> <checksums-url> <artifact-name>
    local url="$1" dest="$2" sums="$3" name="$4" want got
    # --check is a rehearsal: it describes and downloads nothing. The
    # install that follows is wrapped in run_cmd and is skipped too, so
    # the two halves stay consistent — a rehearsal that fetched the
    # bytes and then did not install them would be doing the slow half
    # of the work and none of the useful half.
    if [[ "$CHECK_MODE" == "true" ]]; then
        log_info "[check] would download $name and check it against $sums"
        return 0
    fi
    want="$(fetch_sha256 "$sums" "$name")" || die "could not read the published \
checksum of $name at $sums — nothing was installed. This is a «could not evaluate», \
not a failure of the artifact: check egress and run the phase again."
    retry_net 3 curl -fsSLo "$dest" "$url" || die "could not download $url"
    got="$(sha256sum "$dest" | awk '{print $1}')"
    if [[ "$got" != "$want" ]]; then
        rm -f "$dest"
        die "CHECKSUM MISMATCH on $name: its publisher says $want and what arrived is \
$got. NOTHING was installed and the download was deleted. Either the transfer was \
corrupted, or the bytes are not the ones that were published — and the second one is \
not something to retry past."
    fi
    log_ok "$name verified against the sha256 its publisher publishes"
}

# ── the alignment lane (AEGIS_HOST_ALIGN=1) ─────────────────────────
# Drift between the installed binary and the pin is a QUESTION on a
# host with history — that is what the RED below is for, and it stays
# the default. But inside an update window the drift is not a question,
# it is the job: the window has already raised the pin in group_vars
# and is asking this phase to make the host match. Without this lane
# the window would stop at a RED nobody is awake to answer, and with
# --non-interactive it would be worse — the RED self-confirms, the old
# binary stays, and the window reports a bump that never happened.
host_align() { [[ "${AEGIS_HOST_ALIGN:-0}" == 1 ]]; }

# ── per-tool installation (idempotent: if present and the pin
#    matches, skip; if present with ANOTHER version, warn and do NOT
#    overwrite without a RED — unless the caller is a window that
#    asked for alignment) ───────────────────────────────────────────
# tool_version: the first x.y[.z] string the binary emits. Every tool
# prints its version differently; the regex is the common minimum.
tool_version() {
    local tool="$1"
    case "$tool" in
        kubectl) kubectl version --client 2>/dev/null ;;
        *)       "$tool" --version 2>/dev/null || "$tool" version 2>/dev/null ;;
    esac | grep -om1 '[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?' | head -n1 || echo unknown
    # head -n1: -m1 stops at the first matching LINE, but -o prints every
    # match IN it — helm's BuildInfo carries "v3.17.0" and "go1.23.4" on
    # one line, and the version came back as two (2026-08-27, VPS).
}

# install_binary <tool> <pin> — WHERE each tool comes from and how its
# bytes are proved. Split out of install_tool so the alignment lane can
# call the very same code: a window that raises a pin must install it
# through the path the fresh install uses, or the two drift and only
# one of them is ever exercised.
GH_REL="https://github.com"
install_binary() {
    local tool="$1" pin="$2"
    case "$tool" in
        tofu)
            # Was `curl | bash` of get.opentofu.org until the P1.10
            # audit, which made the pin decorative; it is a versioned
            # .deb since then, and now the .deb is proved too. apt is
            # what installs it (a local path is still a package), so
            # dpkg keeps the record.
            fetch_verified \
                "$GH_REL/opentofu/opentofu/releases/download/v${pin}/tofu_${pin}_amd64.deb" \
                /tmp/tofu.deb \
                "$GH_REL/opentofu/opentofu/releases/download/v${pin}/tofu_${pin}_SHA256SUMS" \
                "tofu_${pin}_amd64.deb"
            run_cmd apt_locked install -y /tmp/tofu.deb
            rm -f /tmp/tofu.deb ;;
        sops)
            # THE .deb IS NOT PUBLISHED WITH A CHECKSUM. sops signs a
            # checksums.txt with cosign keyless, and that file covers
            # the raw binaries and not the packages — checked against
            # v3.9.4 and v3.13.3 on 2026-09-18, both the same. So sops
            # arrives as the binary that IS covered, the way kubectl,
            # helm and cosign already did. On a host where a previous
            # run installed the .deb, dpkg's copy stays at /usr/bin and
            # this one lands in /usr/local/bin, which comes first on
            # PATH; the gate below is what proves which one answers.
            fetch_verified \
                "$GH_REL/getsops/sops/releases/download/v${pin}/sops-v${pin}.linux.amd64" \
                /tmp/sops \
                "$GH_REL/getsops/sops/releases/download/v${pin}/sops-v${pin}.checksums.txt" \
                "sops-v${pin}.linux.amd64"
            run_cmd sudo install -m755 /tmp/sops /usr/local/bin/sops
            rm -f /tmp/sops ;;
        kubectl)
            fetch_verified \
                "https://dl.k8s.io/release/v${pin}/bin/linux/amd64/kubectl" \
                /tmp/kubectl \
                "https://dl.k8s.io/release/v${pin}/bin/linux/amd64/kubectl.sha256" \
                kubectl
            run_cmd sudo install -m755 /tmp/kubectl /usr/local/bin/kubectl
            rm -f /tmp/kubectl ;;
        helm)
            # Was the worst of the five: `curl | bash` of get-helm-3
            # taken from the MAIN branch of helm/helm — an unpinned
            # script, fetched over an unauthenticated artifact path,
            # given a shell and root. The tarball helm publishes for
            # the pinned version carries its own .sha256sum beside it.
            fetch_verified \
                "https://get.helm.sh/helm-v${pin}-linux-amd64.tar.gz" \
                /tmp/helm.tgz \
                "https://get.helm.sh/helm-v${pin}-linux-amd64.tar.gz.sha256sum" \
                "helm-v${pin}-linux-amd64.tar.gz"
            run_cmd rm -rf /tmp/helm-x
            run_cmd mkdir -p /tmp/helm-x
            run_cmd tar -xzf /tmp/helm.tgz -C /tmp/helm-x
            run_cmd sudo install -m755 /tmp/helm-x/linux-amd64/helm /usr/local/bin/helm
            rm -rf /tmp/helm.tgz /tmp/helm-x ;;
        cosign)
            # cosign cannot verify its own arrival: this is the run in
            # which it is being installed, so `cosign verify-blob` has
            # no cosign to run it. The published checksum is what there
            # is, and it is what the release's own signature covers.
            fetch_verified \
                "$GH_REL/sigstore/cosign/releases/download/v${pin}/cosign-linux-amd64" \
                /tmp/cosign \
                "$GH_REL/sigstore/cosign/releases/download/v${pin}/cosign_checksums.txt" \
                cosign-linux-amd64
            run_cmd sudo install -m755 /tmp/cosign /usr/local/bin/cosign
            rm -f /tmp/cosign ;;
        *)
            # Everything else is the distribution's, and the
            # distribution's signature is the proof. A tool that lands
            # here MUST be pinned `apt` in group_vars (that is what
            # check 211 demands of the artifact), because apt installs
            # the line's current version and no number here would be
            # true.
            #
            # And it is demanded of the INSTANCE too, right here, which
            # is not the same thing: the check reads the seed, and the
            # file this phase reads is the instance's own copy, which is
            # allowed to have drifted. Found on 2026-09-18 by rehearsing
            # a window against the live platform — `age: "1.2.1"` was
            # still there, `aegis update` read it as a real pin and
            # layer 2 would have proposed a bump that ends here, where
            # apt installs whatever Ubuntu ships and the alignment then
            # fails with a message about PATH that explains nothing.
            if [[ "$pin" != apt ]]; then
                die "«$tool» is pinned at «$pin» and this phase installs it with apt, \
which installs whatever the distribution's line carries. The number is not delivered by \
anything and an update window would propose a bump nobody can install. Write \
$tool: \"apt\" in $PINS_FILE, or give it a download branch with a published checksum."
            fi
            run_cmd retry_net 3 pkg_install "$tool" ;;
    esac
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
            if host_align; then
                # The window's lane. It does not ask, and it does not
                # believe itself either: the version is read again from
                # the binary that now answers on PATH, and a mismatch
                # here is fatal. The failure this forbids is the one
                # that costs the most — a window that reports
                # «userland: 3.9.4 → 3.13.3» while the host still runs
                # the old one, and an acceptance that passes because
                # nothing actually changed.
                log_info "AEGIS_HOST_ALIGN=1: installing the pin instead of asking"
                install_binary "$tool" "$pin"
                hash -r
                ver="$(tool_version "$tool")"
                [[ "$ver" == "$pin"* ]] || die "alignment of $tool did not take: after \
installing the pin $pin, the binary that answers on PATH still says $ver (\
$(command -v "$tool")). A package-managed copy earlier on PATH is the usual cause."
                log_ok "$tool aligned to the pin $pin"
                return 0
            fi
            gate_red "continue with $tool $ver (≠ pin $pin) — or abort and align the pin/host"
        fi
        return 0
    fi
    # P1.10 audit 2026-07-18: (a) EVERY download with retry_net — they
    # were single-attempt against the mobile network; (b) tofu was
    # installing LATEST via curl|bash (the pin was read and NOT used —
    # a non-reproducible run): now it goes through the VERSIONED .deb
    # from releases. 2026-09-18 closes the note that followed that one
    # («per-artifact sha256 checksums: deferred»): they are not
    # maintained here, they are read from the publisher at install
    # time, which is install_binary above.
    install_binary "$tool" "$pin"
    # REAL post-install verification (real capability, not a proxy):
    gate "instalado-$tool" command -v "$tool"
}

log_info "Installing the pinned userland…"
run_cmd retry_net 3 pkg_update
# apt deps BEFORE the loop (P0.5 audit): read_pin uses pyyaml —
# installing it AFTER the loop was a race against Ubuntu minimal
# (without python3-yaml preinstalled, the first read_pin died with a
# misleading "missing pin" die). htpasswd is in apache2-utils;
# python3-venv for phase 20's ansible venv (bug 3 validation #3:
# Ubuntu minimal does not ship ensurepip). Canonical names: lib/pkg.sh
# says what each is called on this family (htpasswd is apache2-utils on
# debian, apache on arch; python's venv needs nothing on arch):
run_cmd retry_net 3 pkg_install htpasswd python3-yaml python3-venv rsync
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
# The units, the README and two protocols name /usr/local/share/aegis
# as where share/ lives. Nothing created it until 2026-09-20: two
# documented install recipes copied from a path that did not exist.
run_cmd sudo ln -sfn "$AEGIS_ROOT/share" /usr/local/share/aegis
gate "aegis-share-en-su-sitio" test -f /usr/local/share/aegis/systemd/aegis-backup.timer

# ── the user clocks ─────────────────────────────────────────────────
# THE UNITS THAT KEEP AN INSTANCE ALIVE BETWEEN RUNS: the backup, the
# host metrics, the update notice. They are USER units because the
# capture needs the operator's age key and the metrics need nobody's
# root. No phase installed them until 2026-09-20; measured on the house
# machine on 2026-09-16, the units had never been installed and the
# copies were three days old, while every dashboard looked healthy.
# backup.env is DERIVED from the paths this phase knows, never copied
# from a README: systemd starts the service with no profile, so the
# key's path in particular has to be written down here.
USER_UNITS="$HOME/.config/systemd/user"
CLOCKS=(aegis-backup aegis-host-metrics aegis-update-notice)
if systemctl --user show-environment >/dev/null 2>&1; then
    run_cmd mkdir -p "$USER_UNITS" "$HOME/.config/aegis"
    run_cmd bash -c "umask 077; printf 'AEGIS_HOME=%s\nAEGIS_ROOT=%s\nPATH=/usr/local/bin:/usr/bin:/bin\nSOPS_AGE_KEY_FILE=%s\n' \
        '$AEGIS_HOME' '$AEGIS_ROOT' '${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/aegis.key}' > '$HOME/.config/aegis/backup.env'"
    for _c in "${CLOCKS[@]}"; do
        run_cmd install -m 644 "$AEGIS_ROOT/share/systemd/$_c.service" "$AEGIS_ROOT/share/systemd/$_c.timer" "$USER_UNITS/"
    done
    run_cmd systemctl --user daemon-reload
    for _c in "${CLOCKS[@]}"; do
        run_cmd systemctl --user enable --now "$_c.timer"
    done
    # linger: or the clocks stop the moment the operator logs out
    run_cmd sudo loginctl enable-linger "$USER"
    gate "user-clocks-installed" bash -c \
        'for c in aegis-backup aegis-host-metrics aegis-update-notice; do systemctl --user is-enabled "$c.timer" >/dev/null 2>&1 || exit 1; done'
    # ENABLED IS NOT SCHEDULED. A timer can be active and enabled and
    # have no next run (the OnUnitActiveSec trap above); what proves a
    # clock is a next appointment, read off systemd.
    #
    # CONVERGE BEFORE MEASURING. On a machine that has been up longer
    # than the timers' OnBootSec, `enable --now` makes them fire THAT
    # second, and while their service runs systemd has no next elapse
    # yet. The first Vultr VM of the lab (2026-09-22) failed this gate
    # in exactly that second; three seconds later all three clocks had
    # their appointment and all three services had ended in success. A
    # clock that never gets one in two minutes is the real failure.
    _clocks_scheduled() {
        local c
        for c in "${CLOCKS[@]}"; do
            timer_next_elapse --user "$c.timer" >/dev/null || return 1
        done
    }
    gate "user-clocks-have-a-next-run" \
        wait_for 120 3 "the three user clocks have a next run" _clocks_scheduled
    gate "linger-enabled" bash -c "loginctl show-user '$USER' -p Linger 2>/dev/null | grep -q '=yes'"
else
    gate_red "there is no user session bus (systemctl --user cannot be reached: an ssh session without linger, or XDG_RUNTIME_DIR unset). The three clocks were NOT installed. Remedy: loginctl enable-linger $USER, log in again, and run: aegis init --only 05-host"
fi

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
