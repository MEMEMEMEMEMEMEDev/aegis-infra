#!/usr/bin/env bash
# lib/paths.sh — the ONLY place where it is decided where each thing is.
#
# Product != instance (02 §1). In v2 they were the same folder, so nobody
# ever had to choose: the artifact's repo was also the directory where
# platform/, .init-state/ and the store lived. When the instance moved on
# by itself, that double role became half of the debt
# (docs/cli/inconsistencies.md F1-F4).
#
#   AEGIS_ROOT  the PRODUCT — this repo, versioned, read-only for the
#               duration of a run: bin/ libexec/ lib/ init/ verify/
#               seed/.
#   AEGIS_HOME  the INSTANCE — mutable, belonging to this machine:
#               platform/ .init-state/ .state-secrets/ .age-public
#               aegis.conf.
#
# Every v2 command recomputed this from its own __file__ (six copies of
# the same line: aegis-org:32, aegis-app:96, aegis-edge:45,
# aegis-destroy:26, aegis-backup:21, aegis-restore:15) and they were
# exactly the kind of dependency invisible to a grep that C1/C2 of the
# register names. Here there is one.
#
# This file depends on NOTHING: it is sourced both by common.sh (and
# with it the whole init) and by the commands that have to work with a
# broken init (destroy/backup/restore). Its python equivalent is
# lib/aegis/paths.py, which reads the SAME environment variables.

: "${AEGIS_ROOT:?paths.sh needs AEGIS_ROOT (the product) — bin/aegis exports it; a libexec invoked by hand resolves it with the canonical preamble (V-102)}"

aegis_home() {
    if [[ -n "${AEGIS_HOME:-}" ]]; then printf '%s\n' "$AEGIS_HOME"; return 0; fi
    # Compatibility with the v2 shape: if the product has a platform/
    # beside it, THAT is the instance (which is how the house machine is
    # today, and how it stays until v3 is ready — nothing is migrated by
    # force).
    if [[ -d "$AEGIS_ROOT/platform" ]]; then printf '%s\n' "$AEGIS_ROOT"; return 0; fi
    printf '%s\n' "$HOME/aegis"
}

export AEGIS_HOME="${AEGIS_HOME:-$(aegis_home)}"
: "${PLATFORM_DIR:=$AEGIS_HOME/platform}"
: "${AEGIS_STATE_DIR:=$AEGIS_HOME/.init-state}"
: "${AEGIS_SECRETS_DIR:=$AEGIS_HOME/.state-secrets}"
: "${AEGIS_CONF:=$AEGIS_HOME/aegis.conf}"
export PLATFORM_DIR AEGIS_STATE_DIR AEGIS_SECRETS_DIR AEGIS_CONF
