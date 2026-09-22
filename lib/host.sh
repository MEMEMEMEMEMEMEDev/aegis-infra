#!/usr/bin/env bash
# lib/host.sh — is this a machine aegis can install on? Asked FIRST.
#
# WHY THIS EXISTS (2026-09-22). The first person to install aegis on a
# machine that was not Ubuntu (CachyOS, an Arch derivative: pacman, no
# apt) ended with a sudoers drop-in, IPv6 switched off, a half-installed
# k3s and a wizard answered for nothing. The only question «is this
# Ubuntu?» lived in the Ansible playbook of phase 20; before it, the
# preflight had written to /etc and phase 00 had only WARNED about the
# version and gone on. The preflight's `apt-get` calls failed in silence.
#
# The rule is one and it lives here: Ubuntu, version 24.04 or newer —
# the same thing bootstrap-host.yml asserts, because that playbook is
# where the install really stops being possible (apt, AppArmor, the
# kernel modules it loads). A derivative (Mint, Pop!_OS) reports its own
# `distribution` to Ansible and is refused there too, so it is refused
# here, before anything is touched, instead of halfway.
#
# Called before the first `sudo` of `aegis preflight`, before the phase
# loop of `aegis init` (so --from and --only cannot step around it), and
# at the top of phase 00.

AEGIS_HOST_MIN_UBUNTU="24.04"

# host_os_release_file — overridable so the check can feed it fixtures
host_os_release_file() { printf '%s\n' "${AEGIS_OS_RELEASE:-/etc/os-release}"; }

# host_supported — rc 0 when aegis can install here; rc 1 with the reason
# on stderr (stdout stays clean: callers capture nothing, but the house
# rule holds everywhere).
host_supported() {
    local f id="" ver="" pretty=""
    f="$(host_os_release_file)"
    if [[ ! -r "$f" ]]; then
        echo "this machine has no $f: it is not a Linux aegis knows how to install on" >&2
        return 1
    fi
    # read the three fields without sourcing a file that is not ours
    id="$(sed -nE 's/^ID="?([^"]*)"?$/\1/p' "$f" | head -1)"
    ver="$(sed -nE 's/^VERSION_ID="?([^"]*)"?$/\1/p' "$f" | head -1)"
    pretty="$(sed -nE 's/^PRETTY_NAME="?([^"]*)"?$/\1/p' "$f" | head -1)"
    if [[ "$id" != "ubuntu" ]]; then
        echo "this machine runs ${pretty:-${id:-an unknown system}}, and aegis installs only on Ubuntu $AEGIS_HOST_MIN_UBUNTU or newer (it uses apt and Ubuntu's kernel and AppArmor defaults)" >&2
        return 1
    fi
    if [[ -z "$ver" ]] || [[ "$(printf '%s\n%s\n' "$AEGIS_HOST_MIN_UBUNTU" "$ver" | sort -V | head -1)" != "$AEGIS_HOST_MIN_UBUNTU" ]]; then
        echo "this machine runs ${pretty:-Ubuntu ${ver:-?}}, and aegis needs Ubuntu $AEGIS_HOST_MIN_UBUNTU or newer" >&2
        return 1
    fi
    return 0
}
