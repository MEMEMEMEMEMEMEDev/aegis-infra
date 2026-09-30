# title: the preflight asks the resolver every program uses, not systemd-resolved's own tool
# origin: new in v3 — 2026-09-23, lab-debian13: Debian 13 ships no systemd-resolved, `resolvectl query` was «command not found», and a working DNS was reported as 0/3
check() {
# THE PROPERTY: «does github.com resolve?» is asked the way curl, git
# and apt ask it (getaddrinfo, through nsswitch), which works with and
# without systemd-resolved. Read out of the 3/9 block, and DRIVEN: the
# probe's own lines run on a PATH with no resolvectl, once with a
# resolver that answers (must say 3/3) and once with one that does not
# (must say unstable). A probe that counts without asking passes the
# first and is caught by the second.
D238=""
P238="$LIBEXEC/aegis-preflight"
[[ -f "$P238" ]] || { fail "there is no aegis preflight"; return; }
B238="$(sed -n '/== 3\/9 DNS/,/== 4\/9/p' "$P238" | nc)"
[[ -n "$B238" ]] || { fail "the preflight has no 3/9 DNS step to read"; return; }
grep -qE 'resolvectl[[:space:]]+query' <<< "$(nc "$P238")" \
    && D238="$D238 the preflight still asks resolvectl query (command not found where systemd-resolved is not installed);"
PROBE238="$(grep -E '^R=0; for i in 1 2 3; do|^\[ "\$R" -eq 3 \]' <<< "$B238")"
(( $(grep -c . <<< "$PROBE238") == 2 )) \
    || D238="$D238 the DNS probe is not the two lines this check drives (a count loop and its verdict);"
grep -qE 'getent ahosts github\.com' <<< "$PROBE238" \
    || D238="$D238 the DNS probe does not ask getaddrinfo (getent ahosts);"
if [[ -z "$D238" ]]; then
    T238="$(mktemp -d)"
    mkdir -p "$T238/yes" "$T238/no"
    printf '#!/bin/sh\necho "192.0.2.10 STREAM github.com"\n' > "$T238/yes/getent"
    printf '#!/bin/sh\nexit 2\n' > "$T238/no/getent"
    chmod +x "$T238/yes/getent" "$T238/no/getent"
    for side in yes no; do
        # PATH is ONLY the fake resolver: the probe's other words are
        # bash builtins, and a resolvectl on this machine stays invisible
        out="$(PATH="$T238/$side" "$BASH" -c \
            'ok(){ echo "OK $1"; }; bad(){ echo "BAD $1"; }; '"$PROBE238" 2>&1)"
        case "$side:$out" in
            yes:"OK github.com resolves 3/3") ;;
            yes:*) D238="$D238 with a resolver that answers and no resolvectl, the probe said «${out:0:80}»;" ;;
            no:BAD*) ;;
            no:*) D238="$D238 with a resolver that does NOT answer, the probe said «${out:0:80}»: it counts without asking;" ;;
        esac
    done
    rm -rf "$T238"
fi
if [[ -n "$D238" ]]; then
    fail "the preflight's DNS verdict still depends on systemd-resolved:$D238"
else
    pass "the 3/9 DNS probe asks getaddrinfo (getent ahosts) three times, and driven without resolvectl it says 3/3 when the resolver answers and unstable when it does not"
fi
}
