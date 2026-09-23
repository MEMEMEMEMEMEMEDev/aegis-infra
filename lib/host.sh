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
# The rule lives here and bootstrap-host.yml asserts the same one from
# Ansible's own facts, because that playbook is where the install really
# stops being possible. A derivative (Mint, Pop!_OS) reports its own
# `distribution` to Ansible and is refused there too, so it is refused
# here, before anything is touched, instead of halfway.
#
# FAMILIES (2026-09-23). The rule is a list of families, not one name:
#   AEGIS_HOST_FAMILIES_KNOWN  the families the product has code for
#                              (the playbook has a branch for each);
#   AEGIS_HOST_SUPPORTED_DEFAULT  the families aegis is SUPPORTED on. A
#                              family joins it only with an archived,
#                              clean, complete run on it — having the
#                              code is not the same as having run.
# AEGIS_HOST_SUPPORTED (environment, comma-separated) widens the list for
# a lab run on a family that has code but no archived run yet. It can
# only name KNOWN families, and it says so on stderr every time.
#
# Called before the first `sudo` of `aegis preflight`, before the phase
# loop of `aegis init` (so --from and --only cannot step around it), and
# at the top of phase 00.

AEGIS_HOST_MIN_UBUNTU="24.04"
AEGIS_HOST_MIN_DEBIAN="13"     # 12 ships python 3.11; ansible==14 needs 3.12
AEGIS_HOST_FAMILIES_KNOWN="ubuntu debian"
AEGIS_HOST_SUPPORTED_DEFAULT="ubuntu"

# host_os_release_file — overridable so the check can feed it fixtures
host_os_release_file() { printf '%s\n' "${AEGIS_OS_RELEASE:-/etc/os-release}"; }

# _host_field <name> — one field of os-release, without sourcing a file
# that is not ours
_host_field() {
    sed -nE "s/^$1=\"?([^\"]*)\"?$/\\1/p" "$(host_os_release_file)" 2>/dev/null | head -1
}

# host_family — ubuntu | debian | arch | rhel | unknown, on stdout.
# By ID first. ID_LIKE only maps an Arch derivative (CachyOS says
# ID=cachyos ID_LIKE=arch) and the RHEL family, which is named so it can
# be refused BY NAME. An Ubuntu or Debian derivative (Mint, Pop!_OS,
# Kali) is NOT mapped to its parent: it reports its own distribution to
# Ansible, and nobody has measured it.
host_family() {
    local id like
    id="$(_host_field ID)"; like="$(_host_field ID_LIKE)"
    case "$id" in
        ubuntu|debian|arch) printf '%s\n' "$id"; return 0 ;;
        fedora|rhel|centos|rocky|almalinux) printf 'rhel\n'; return 0 ;;
    esac
    case " $like " in
        *" arch "*) printf 'arch\n' ;;
        *" rhel "*|*" fedora "*) printf 'rhel\n' ;;
        *) printf 'unknown\n' ;;
    esac
}

# host_supported_families — the list in force, one per line, on stdout.
# rc 1 (reason on stderr) when the override names a family with no code.
host_supported_families() {
    local raw="${AEGIS_HOST_SUPPORTED:-$AEGIS_HOST_SUPPORTED_DEFAULT}" f
    raw="${raw//,/ }"
    for f in $raw; do
        if [[ " $AEGIS_HOST_FAMILIES_KNOWN " != *" $f "* ]]; then
            echo "AEGIS_HOST_SUPPORTED names «$f», and aegis has no code for that family (it knows: $AEGIS_HOST_FAMILIES_KNOWN)" >&2
            return 1
        fi
        printf '%s\n' "$f"
    done
}

# _host_describe_list — «Ubuntu 24.04 or newer» / «…, Debian 13 or newer»
_host_describe_list() {
    local f out=()
    for f in "$@"; do
        case "$f" in
            ubuntu) out+=("Ubuntu $AEGIS_HOST_MIN_UBUNTU or newer") ;;
            debian) out+=("Debian $AEGIS_HOST_MIN_DEBIAN or newer") ;;
        esac
    done
    local IFS=','; printf '%s' "${out[*]}" | sed 's/,/, /g'
}

# host_supported — rc 0 when aegis can install here; rc 1 with the reason
# on stderr (stdout stays clean: callers capture nothing, but the house
# rule holds everywhere).
host_supported() {
    local f fam ver pretty min raw list=()
    f="$(host_os_release_file)"
    if [[ ! -r "$f" ]]; then
        echo "this machine has no $f: it is not a Linux aegis knows how to install on" >&2
        return 1
    fi
    # a list aegis cannot act on accepts NOTHING (its reason is already
    # on stderr): a typo in a lab override must not read as «any Linux»
    if ! raw="$(host_supported_families)" || [[ -z "$raw" ]]; then
        echo "the list of host families is not one aegis can act on: nothing is accepted" >&2
        return 1
    fi
    mapfile -t list <<<"$raw"
    if [[ "${list[*]}" != "$AEGIS_HOST_SUPPORTED_DEFAULT" ]]; then
        echo "note: AEGIS_HOST_SUPPORTED widens the host list to «${list[*]}» — a lab run, not a supported install" >&2
    fi
    fam="$(host_family)"
    ver="$(_host_field VERSION_ID)"
    pretty="$(_host_field PRETTY_NAME)"
    if [[ " ${list[*]} " != *" $fam "* ]]; then
        echo "this machine runs ${pretty:-an unknown system}, and aegis installs only on $(_host_describe_list "${list[@]}") (it installs with that family's package manager, kernel and security defaults)" >&2
        return 1
    fi
    case "$fam" in
        ubuntu) min="$AEGIS_HOST_MIN_UBUNTU" ;;
        debian) min="$AEGIS_HOST_MIN_DEBIAN" ;;
        *)      min="" ;;
    esac
    if [[ -n "$min" ]] && { [[ -z "$ver" ]] || [[ "$(printf '%s\n%s\n' "$min" "$ver" | sort -V | head -1)" != "$min" ]]; }; then
        echo "this machine runs ${pretty:-$fam ${ver:-?}}, and aegis needs $(_host_describe_list "$fam")" >&2
        return 1
    fi
    return 0
}
