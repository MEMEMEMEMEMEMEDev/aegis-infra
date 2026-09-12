# title: the traffic is attributed to the organization the generator actually named
# origin: new in v3 — 2026-09-11, `aegis traffic` reads a label built by two files that do not know each other
check() {
# A COUPLING NOBODY CAN SEE FROM EITHER SIDE.
#
# traefik labels each series with the CRD service it routed to, and for
# a tenant that name is assembled from two things `lib/aegis/org.py`
# writes — the namespace `org-<organization>` and the IngressRoute
# `<organization>-ruteo`. traefik joins them into
#
#     org-<organization>-<organization>-ruteo-<hash>@kubernetescrd
#
# and `aegis traffic` turns that back into a dimension with one regular
# expression. NOTHING in either file mentions the other.
#
# So: rename the route in the generator and the expression keeps
# compiling, keeps being accepted by vmsingle, and returns rows that
# belong to nobody — or, worse, to the wrong organization. Every traffic
# panel would be confidently wrong and not one thing would go red. It is
# the same class as the FROM nobody was reading: it does not fail, it
# succeeds with different meaning.
#
# The check derives both shapes from the generator and runs the real
# expression against them in python. No cluster, no metrics, no window.
#
# It also asks that the platform's own traffic be queried as the
# NEGATION of that shape: argocd's requests summed into a tenant would
# invent visitors it never had.
D130=""
[[ -f "$LIBEXEC/aegis-traffic" ]] || { skip "there is no traffic command yet: nothing attributes anything"; return; }

OUT130="$(python3 "$AEGIS_ROOT/verify/checks/130.py" "$AEGIS_ROOT" 2>&1)"
RC130=$?
if (( RC130 != 0 )); then
    fail "the reader of check 130 itself failed (rc $RC130) and the attribution was never measured: $OUT130"
    return
fi
SCOPE130=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE130="${hit#SCOPE: }" ;;
        *)       D130="$D130 $hit;" ;;
    esac
done <<< "$OUT130"

printf '    %s\n' "${SCOPE130:-the scope was not reported}"
if [[ -n "$D130" ]]; then
    fail "the traffic would be credited to the wrong organization, or to none:$D130"
else
    pass "the attribution pattern matches the route names the generator produces, reads the right organization out of them, and the platform's traffic is asked for apart ($SCOPE130)"
fi
}
