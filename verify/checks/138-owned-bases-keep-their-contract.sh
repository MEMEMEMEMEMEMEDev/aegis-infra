# title: every base aegis owns keeps its contract: internal FROM, port 8080, numeric USER, config checked
# origin: new in v3 — 2026-08-27, the day aegis-base-nginx replaced a third-party base nobody could patch
check() {
# base-images/<member>/Containerfile is a base image aegis OWNS: alpine
# + apk upgrade + the distribution's package, rebuilt by the base-images
# job the morning image-watch finds a fixable CVE, and propagated by
# digest to every consumer. The consumers changed one FROM line and
# nothing else, so what they may assume of the base is a CONTRACT, and
# each clause has a failure that is silent in the pod:
#   · FROM the INTERNAL registry. A base built on an image pulled from
#     the internet stands on a digest nobody mirrored, scanned or
#     signed — the hole the mirror closed on 2026-08-09 reopened one
#     level down.
#   · EXPOSE 8080. A tenant's NetworkPolicy admits edge → 8080 only; an
#     image on 80 starts fine and never receives a request.
#   · the LAST `USER` is numeric. Tenant namespaces are PSS restricted:
#     runAsNonRoot cannot be proven for `USER nginx` (the kubelet does
#     not read /etc/passwd) and the pod is rejected at admission.
#   · if the image installs nginx, it runs `nginx -t` at build time:
#     the include of conf.d in the wrong context fails HERE, not in
#     the consumer's pod. Generalised the simplest honest way: the
#     config check is demanded of the server the base installs, and
#     nginx is the only server the seed knows how to demand it of.
# Besides the members, the job and the propagation list have to be
# there: base-images/Jenkinsfile is what asserts the contract before
# pushing, and consumers.txt carries the derived block aegis-org
# rewrites — without its two sentinels the generator has nowhere to
# write and the consumers never get the new digest.
# Zero members is red: the seed ships nginx, and a base-images/ with
# nothing in it is a job that builds nothing and reports success.
B="$P/base-images"
[[ -d "$B" ]] || { fail "$B does not exist: the platform owns no base image (the seed ships aegis-base-nginx)"; return; }
D138=""
REG='registry.registry-system.svc.cluster.local:5000/'
members=0
for cf in "$B"/*/Containerfile; do
    [[ -f "$cf" ]] || continue
    members=$((members+1))
    m="$(basename "$(dirname "$cf")")"
    code="$(joincont "$cf" | grep -vE '^[[:space:]]*#')"
    from="$(grep -E '^[[:space:]]*FROM[[:space:]]' <<< "$code" | head -1)"
    [[ -z "$from" ]] && D138="$D138 $m: no FROM;"
    [[ -n "$from" && "$from" != *"FROM $REG"* && "$from" != *"FROM --platform="*" $REG"* ]] \
        && D138="$D138 $m: FROM does not name the internal registry ($REG…): a base built on the internet stands on a digest nobody mirrored, scanned or signed;"
    grep -qE '^[[:space:]]*EXPOSE[[:space:]]+8080([[:space:]]|$)' <<< "$code" \
        || D138="$D138 $m: no EXPOSE 8080 (a tenant's NetworkPolicy admits only 8080: on any other port the pod starts and never receives a request);"
    last_user="$(grep -E '^[[:space:]]*USER[[:space:]]' <<< "$code" | tail -1 | awk '{print $2}')"
    if [[ -z "$last_user" ]]; then
        D138="$D138 $m: no USER: the image runs as root and PSS restricted rejects it at admission;"
    elif ! [[ "$last_user" =~ ^[0-9]+(:[0-9]+)?$ ]]; then
        D138="$D138 $m: the last USER is '$last_user', not numeric: runAsNonRoot cannot be proven for a name and the pod is rejected at admission;"
    fi
    if grep -qE 'apk[[:space:]]+add[^&|;]*[[:space:]]nginx([[:space:]]|$)' <<< "$code"; then
        grep -qE '^[[:space:]]*RUN[[:space:]].*nginx[[:space:]]+-t([[:space:]]|$)' <<< "$code" \
            || D138="$D138 $m: installs nginx and never runs \`nginx -t\`: a conf.d included in the wrong context fails in the consumer's pod instead of here;"
    fi
done
(( members > 0 )) || D138="$D138 base-images/ has no <member>/Containerfile: a job that builds nothing and reports success (the seed ships nginx);"
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
else pass "$members owned base(s): internal FROM, EXPOSE 8080, numeric USER, config checked where a server is installed; the job and the consumers list with both sentinels are there"; fi
}
