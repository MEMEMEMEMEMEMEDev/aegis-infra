#!/bin/sh
# base-images/siblings.sh — a member that stands on another member.
#
# php's Containerfile takes its nginx from aegis-base-nginx (`FROM
# …/aegis-base-nginx:<tag>@sha256:… AS nginxbin`). That pin is a digest
# born in ONE registry: the seed carries the house's build 9, and in a
# clean instance that digest does not exist. Phase 80 fires every member
# in one run; php was built with the pin it was shipped with and died
# MANIFEST_UNKNOWN, and only the propagation of the nginx just built
# fixed the pin — for the NEXT run. A clean install needed two passes,
# and the second one only happened because a harmless line was read as
# a network failure (plan/18 §5, findings 14 and 13, 2026-09-23). The
# same order hurts a house that already works: image-watch naming
# «php nginx» for one CVE built php on the OLD nginx, the one with the
# CVE, and signed it.
#
# So a run resolves its own members: a member is built AFTER the members
# of the same run it stands on, and its FROM is pinned to what THIS run
# built for them. A member the run does not rebuild keeps the pin its
# Containerfile carries (propagation keeps that pin current).
#
#   order <member>...  the members, one per line, each after the ones of
#                      the SAME list it stands on; a cycle is an error.
#   pin <member>       rewrites, in this checkout, every FROM of
#                      <member>/Containerfile that names a member of the
#                      run. Reads the run from the environment:
#                        RUN_MEMBERS  the members of this run
#                        BUILT_REFS   "name=tag@sha256:… …", the ones built
#                        FAILED_NOW   the ones that failed
#                      A sibling that failed, or that has not been built
#                      yet, stops the member here: a MANIFEST_UNKNOWN deep
#                      in kaniko says nothing about why.
#
# POSIX sh: it runs in the agent's jnlp container, next to git and sed.
set -eu
cd "$(dirname "$0")"

# The members that <member>'s FROM lines name, once each.
siblings_of() {
    sed -n -E 's#^[[:space:]]*FROM[[:space:]]+([^[:space:]]*/)?aegis-base-([a-z0-9-]+)[:@].*#\2#p' \
        "$1/Containerfile" | sort -u
}

order() {
    left="$*"
    while [ -n "$left" ]; do
        ready="" wait=""
        for m in $left; do
            ok=1
            for s in $(siblings_of "$m"); do
                case " $left " in *" $s "*) ok=0 ;; esac
            done
            if [ "$ok" = 1 ]; then ready="$ready $m"; else wait="$wait $m"; fi
        done
        if [ -z "$ready" ]; then
            echo "ERROR: these members stand on each other in a cycle:$wait — none of them can be built first" >&2
            exit 1
        fi
        printf '%s\n' $ready
        left="${wait# }"
    done
}

pin() {
    m="$1"
    for s in $(siblings_of "$m"); do
        case " ${RUN_MEMBERS:-} " in
            *" $s "*) ;;
            *) echo "pin: aegis-base-$s is not rebuilt in this run — $m stands on the pin its Containerfile carries"
               continue ;;
        esac
        case " ${FAILED_NOW:-} " in
            *" $s "*) echo "ERROR: aegis-base-$m stands on aegis-base-$s, which FAILED in this run — nothing to build it on" >&2
                      exit 1 ;;
        esac
        ref=""
        for r in ${BUILT_REFS:-}; do
            case "$r" in "$s="*) ref="${r#*=}" ;; esac
        done
        if [ -z "$ref" ]; then
            echo "ERROR: aegis-base-$s is in this run and has not been built yet — the order put $m before it" >&2
            exit 1
        fi
        sed -i -E "s#(aegis-base-$s)(:[^@[:space:]]+)?@sha256:[0-9a-f]{64}#\\1:$ref#" "$m/Containerfile"
        if ! grep -qF "aegis-base-$s:$ref" "$m/Containerfile"; then
            echo "ERROR: $m/Containerfile names aegis-base-$s without a digest to rewrite — pin it by digest" >&2
            exit 1
        fi
        echo "pin: $m stands on aegis-base-$s:$ref, built in this run"
    done
}

case "${1:-}" in
    order) shift; order "$@" ;;
    pin)   [ $# -eq 2 ] || { echo "usage: $0 pin <member>" >&2; exit 2; }
           pin "$2" ;;
    *)     echo "usage: $0 order <member>... | pin <member>" >&2; exit 2 ;;
esac
