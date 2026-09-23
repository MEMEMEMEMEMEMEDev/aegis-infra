#!/usr/bin/env bash
# lib/pkg.sh — the host's package manager, behind one name per package.
#
# WHY (2026-09-23). aegis called apt-get by name in six places, with
# Ubuntu's package names. Debian shares both; Arch shares neither
# (pacman, `apache` for htpasswd, `python-yaml`, `github-cli`). This file
# is the ONE place that knows which manager a family has and what a
# package is called there. Every caller speaks CANONICAL names.
#
# The table is bash on purpose, not YAML: the preflight reads it BEFORE
# PyYAML exists on the host (python3-yaml is one of its rows).
#
# Names are MEASURED, not recalled: debian on lab-debian13 (apt-cache
# policy, 2026-09-23); arch on archlinux.org's package index the same day
# (registro: plan/01 §2.2). A row that says «-» means the family ships it
# inside something already installed (python's venv on Arch).
#
# Requires lib/host.sh (host_family). Everything logs to stderr.

# pkg_family — the family whose manager this host has: debian | arch.
# Ubuntu is a debian for packages (same manager, same names in the table).
pkg_family() {
    case "$(host_family)" in
        ubuntu|debian) printf 'debian\n' ;;
        arch)          printf 'arch\n' ;;
        *)             printf 'unknown\n' ;;
    esac
}

# pkg_name <canonical> — the family's name on stdout; empty (rc 0) when
# the family needs nothing for it; rc 1 when the name is not in the table.
pkg_name() {
    local c="$1" fam deb arch
    fam="$(pkg_family)"
    case "$c" in
        #  canonical      debian/ubuntu     arch
        htpasswd)         deb=apache2-utils arch=apache ;;
        python3-yaml)     deb=python3-yaml  arch=python-yaml ;;
        python3-venv)     deb=python3-venv  arch=- ;;
        gh)               deb=gh            arch=github-cli ;;
        conntrack)        deb=conntrack     arch=conntrack-tools ;;
        age|jq|git|openssl|direnv|tmux|rsync|curl|ca-certificates|iptables)
                          deb="$c"          arch="$c" ;;
        *) echo "pkg_name: «$c» is not in the package table (lib/pkg.sh)" >&2; return 1 ;;
    esac
    case "$fam" in
        debian) printf '%s\n' "$deb" ;;
        arch)   [[ "$arch" == - ]] || printf '%s\n' "$arch" ;;
        *) echo "pkg_name: this host's family has no package manager aegis knows" >&2; return 1 ;;
    esac
}

# pkg_names <canonical>… — the family's names, one per line (the ones the
# family needs nothing for are left out); rc 1 on a name outside the table.
# For callers that hand the list to someone else (phase 20 → Ansible).
pkg_names() {
    local c n
    for c in "$@"; do
        n="$(pkg_name "$c")" || return 1
        [[ -n "$n" ]] && printf '%s\n' "$n"
    done
    return 0
}

# pkg_update — refresh the package index (debian) / sync and upgrade (arch:
# a partial upgrade, -Sy followed by -S, is unsupported on Arch).
pkg_update() {
    case "$(pkg_family)" in
        debian) sudo apt-get -o DPkg::Lock::Timeout=600 update -qq ;;
        arch)   sudo pacman -Syu --noconfirm --needed ;;
        *) echo "pkg_update: this host's family has no package manager aegis knows" >&2; return 1 ;;
    esac
}

# pkg_install <canonical>… — install by canonical name. apt waits for the
# dpkg lock (a first boot's unattended-upgrades holds it: bug run #10);
# pacman skips what is already there. No `|| true`: a failure is the
# caller's to see.
pkg_install() {
    local c n names=()
    for c in "$@"; do
        n="$(pkg_name "$c")" || return 1
        [[ -n "$n" ]] && names+=("$n")
    done
    (( ${#names[@]} )) || return 0
    case "$(pkg_family)" in
        debian) sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y -qq "${names[@]}" ;;
        arch)   sudo pacman -S --needed --noconfirm --quiet "${names[@]}" ;;
        *) echo "pkg_install: this host's family has no package manager aegis knows" >&2; return 1 ;;
    esac
}

# pkg_is_installed <canonical> — rc 0 when the family's package is there
pkg_is_installed() {
    local n
    n="$(pkg_name "$1")" || return 1
    [[ -n "$n" ]] || return 0
    case "$(pkg_family)" in
        debian) dpkg-query -W -f='${Status}' "$n" 2>/dev/null | grep -q 'install ok installed' ;;
        arch)   pacman -Q "$n" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}
