# title: every base aegis owns keeps its contract: pinned FROM, port 8080, numeric USER, server checked at build
# origin: new in v3 — 2026-08-27, the day aegis-base-nginx replaced a third-party base nobody could patch
check() {
# base-images/<member>/Containerfile is a base image aegis OWNS: alpine
# + apk upgrade + the distribution's package, rebuilt by the base-images
# job the morning image-watch finds a fixable CVE, and propagated by
# digest to every consumer. The consumers changed one FROM line and
# nothing else, so what they may assume of the base is a CONTRACT, and
# each clause has a failure that is silent in the pod:
#   · FROM pinned by DIGEST — the internal registry, or a public
#     reference with `@sha256:`. A bare tag from the internet is a
#     mutable pointer: the hole the mirror closed on 2026-08-09,
#     reopened one level down. The first version demanded the mirror
#     itself, and the same day's measurement showed why that cannot
#     be the rule: the public alpine:3.22 carried the very libcrypto3
#     the mirror's scan refuses, so a base that only exists to run
#     `apk upgrade` on top of it could never be built from a mirror it
#     cannot enter. The alpine underneath never runs; the result is
#     what gets scanned and signed. So: pinned, from anywhere.
#   · EXPOSE 8080. A tenant's NetworkPolicy admits edge → 8080 only; an
#     image on 80 starts fine and never receives a request.
#   · the LAST `USER` is numeric. Tenant namespaces are PSS restricted:
#     runAsNonRoot cannot be proven for `USER nginx` (the kubelet does
#     not read /etc/passwd) and the pod is rejected at admission. Which
#     number is the member's business (nginx runs as 101, node as
#     65532, the uid distroless taught its consumers): the job reads
#     the expected uid from this same line, so the clause here is
#     "numeric", not "101".
#   · if the image installs a server, it RUNS it once at build time.
#     For nginx that is `nginx -t`: the include of conf.d in the wrong
#     context fails HERE, not in the consumer's pod. For nodejs it is
#     `node --version` or `node -e …`: the runtime loads and the core
#     modules are in the package, proven before four backends stand on
#     it. The table below is the whole rule — package installed → RUN
#     line demanded → why — and a third base is one more row.
# The second member arrived the same day as the first: the CVE that
# blocked the static fronts (CVE-2026-14456) surfaced again in the
# libssl3t64 of nodejs-distroless:22, and the upstream candidate digest
# was measured and is not patched either. aegis-base-node is alpine +
# apk upgrade + apk add nodejs, keeping distroless's contract (uid
# 65532, ENTRYPOINT node, port 8080) so the node backends change only
# their FROM.
# Besides the members, the job and the propagation list have to be
# there: base-images/Jenkinsfile is what asserts the contract before
# pushing, and consumers.txt carries the derived block aegis-org
# rewrites — without its two sentinels the generator has nowhere to
# write and the consumers never get the new digest.
# Zero members is red: the seed ships nginx and node, and a base-images/
# with nothing in it is a job that builds nothing and reports success.
B="$P/base-images"
[[ -d "$B" ]] || { fail "$B does not exist: the platform owns no base image (the seed ships aegis-base-nginx and aegis-base-node)"; return; }
D138=""
REG='registry.registry-system.svc.cluster.local:5000/'
# package → the RUN line demanded → its name for the verdict → why.
# One row per server the seed knows how to demand a build-time check
# of; a new base with a new server is one more row, nothing else.
T=$'\t'
SERVERS=(
    "nginx${T}nginx[[:space:]]+-t([[:space:]]|\$)${T}nginx -t${T}a conf.d included in the wrong context fails in the consumer's pod instead of here"
    "nodejs${T}node[[:space:]]+(--version|-e)([[:space:]]|\$)${T}node --version / node -e${T}a runtime that does not load, or a core module the package left out, fails in the consumer's pod instead of here"
)
members=0
for cf in "$B"/*/Containerfile; do
    [[ -f "$cf" ]] || continue
    members=$((members+1))
    m="$(basename "$(dirname "$cf")")"
    code="$(joincont "$cf" | grep -vE '^[[:space:]]*#')"
    from="$(grep -E '^[[:space:]]*FROM[[:space:]]' <<< "$code" | head -1)"
    [[ -z "$from" ]] && D138="$D138 $m: no FROM;"
    if [[ -n "$from" ]] && ! grep -qE "FROM ([^ ]+ )*($(printf '%s' "$REG" | sed 's/\./\\./g')[^ ]+|[^ ]+@sha256:[0-9a-f]{64})([[:space:]]|$)" <<< "$from"; then
        D138="$D138 $m: FROM is neither the internal registry ($REG…) nor a reference pinned by @sha256: — a bare tag from the internet is a mutable pointer, and a base built on it stands on bytes nobody chose;"
    fi
    grep -qE '^[[:space:]]*EXPOSE[[:space:]]+8080([[:space:]]|$)' <<< "$code" \
        || D138="$D138 $m: no EXPOSE 8080 (a tenant's NetworkPolicy admits only 8080: on any other port the pod starts and never receives a request);"
    last_user="$(grep -E '^[[:space:]]*USER[[:space:]]' <<< "$code" | tail -1 | awk '{print $2}')"
    if [[ -z "$last_user" ]]; then
        D138="$D138 $m: no USER: the image runs as root and PSS restricted rejects it at admission;"
    elif ! [[ "$last_user" =~ ^[0-9]+(:[0-9]+)?$ ]]; then
        D138="$D138 $m: the last USER is '$last_user', not numeric: runAsNonRoot cannot be proven for a name and the pod is rejected at admission;"
    fi
    while IFS=$'\t' read -r pkg pat human why; do
        grep -qE "apk[[:space:]]+add[^&|;]*[[:space:]]${pkg}([[:space:]]|$)" <<< "$code" || continue
        grep -qE "^[[:space:]]*RUN[[:space:]].*${pat}" <<< "$code" \
            || D138="$D138 $m: installs $pkg and never runs \`$human\` at build time: $why;"
    done < <(printf '%s\n' "${SERVERS[@]}")
done
(( members > 0 )) || D138="$D138 base-images/ has no <member>/Containerfile: a job that builds nothing and reports success (the seed ships nginx and node);"
[[ -f "$B/Jenkinsfile" ]] || D138="$D138 base-images/Jenkinsfile does not exist: nothing asserts the contract before the push, nothing propagates the digest;"
C="$B/consumers.txt"
if [[ -f "$C" ]]; then
    grep -qF -- '# --- DERIVED by aegis-org (base consumers): do not edit by hand ---' "$C" \
        || D138="$D138 consumers.txt is missing the DERIVED sentinel: aegis-org has nowhere to write the consumers;"
    grep -qF -- '# --- END DERIVED ---' "$C" \
        || D138="$D138 consumers.txt is missing the END DERIVED sentinel;"
else
    D138="$D138 base-images/consumers.txt does not exist: the rebuilt base is propagated to nobody;"
fi
if [[ -n "$D138" ]]; then fail "base-images:$D138"
else pass "$members owned base(s): pinned FROM, EXPOSE 8080, numeric USER, the server run once at build time where one is installed (nginx -t · node -e); the job and the consumers list with both sentinels are there"; fi
}
