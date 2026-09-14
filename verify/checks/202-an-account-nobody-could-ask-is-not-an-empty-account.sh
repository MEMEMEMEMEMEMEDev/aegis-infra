# title: an account nobody could ask is not an empty account
# origin: new in v3 — 2026-09-13, `aegis repos` is the first reading that comes from outside this machine (plan/15 §15)
check() {
# THE PRODUCT'S THESIS, applied to the one reading that does not come
# from this machine. `aegis repos` asks GitHub what the account has, and
# GitHub is behind a network, a token and a rate limit; any of the three
# can be the reason an answer does not arrive.
#
# A screen that drew zero repositories there would tell somebody their
# account is empty, and they would go looking for what happened to their
# work. Every number on that screen would be TRUE of the document in
# front of them, which is the failure this repository filed on
# 2026-09-10 and gave a name.
#
# Three accounts are put in front of the real command with a stub `gh` —
# no network, no token, nothing contacted — and the three have to come
# out different: silent is rc 2 with not one repository drawn, an empty
# account is rc 0 and SAYS it is empty, and a populated one carries what
# claims each repository.
#
# And the claim in both directions: one tree can be a front AND a bff,
# so a repository serving two services has to report both, and a
# repository nothing claims is an OPTION rather than a finding.
D202=""
[[ -f "$LIBEXEC/aegis-repos" ]] || { skip "there is no \`aegis repos\`: this check has no subject"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/202.py" ]] || { fail "check 202 has no sidecar: the three accounts were never compared"; return; }

OUT202="$(python3 "$AEGIS_ROOT/verify/checks/202.py" "$AEGIS_ROOT" 2>&1)"
RC202=$?
if (( RC202 != 0 )); then
    fail "the exercise of check 202 itself failed (rc $RC202) and nothing was asked: $OUT202"
    return
fi
SCOPE202=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE202="${hit#SCOPE: }" ;;
        *)       D202="$D202 $hit;" ;;
    esac
done <<< "$OUT202"

printf '    %s\n' "${SCOPE202:-the scope was not reported}"
if [[ -n "$D202" ]]; then
    fail "the account's repositories are read in a way that can lie about them:$D202"
else
    pass "silent, empty and populated come out as three different answers, and every repository carries the service that claims it ($SCOPE202)"
fi
}
