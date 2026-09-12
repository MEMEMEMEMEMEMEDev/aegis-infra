# title: nothing inside a tenant's namespace goes unnamed
# origin: new in v3 — 2026-09-12, measured on a live instance the first time `aegis tenant show` ran (plan/15 §11)
check() {
# MEASURED, NOT IMAGINED. The first run of `aegis tenant show` against
# this instance found an organization whose contract declares one
# stateless service holding 100Gi on a bound claim that came out of its
# own repo. Nothing looked wrong: Bound, Running, Synced, and the round
# green. `aegis data` had never heard of it, because `aegis data` reads
# CONTRACTS.
#
# That is the shape of the whole class. The contract is what every tool
# here derives from, so anything in the namespace the contract does not
# name is invisible to all of them at once. The only place it can be
# caught is the command that looks at the namespace itself, and only
# while it refuses to walk past what it does not recognise.
#
# The exercise puts a stranger workload and two unclaimed claims —one
# with no `app` label at all, like the real one— in front of the command
# and demands they be NAMED and counted. Drawing them quietly at the
# bottom of a screen is fine; not knowing about them is not.
D133=""
[[ -f "$LIBEXEC/aegis-tenant" ]] || { skip "there is no \`aegis tenant\`: this check has no subject"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/133.py" ]] || { fail "check 133 has no sidecar: the exercise cannot run"; return; }

OUT133="$(python3 "$AEGIS_ROOT/verify/checks/133.py" "$AEGIS_ROOT" 2>&1)"
RC133=$?
if (( RC133 != 0 )); then
    fail "the exercise of check 133 itself failed (rc $RC133) and the namespace was never swept: $OUT133"
    return
fi
SCOPE133=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE133="${hit#SCOPE: }" ;;
        *)       D133="$D133 $hit;" ;;
    esac
done <<< "$OUT133"

printf '    %s\n' "${SCOPE133:-the scope was not reported}"
if [[ -n "$D133" ]]; then
    fail "something lives in a tenant's namespace and no command on this machine knows:$D133"
else
    pass "every workload and every volume in the namespace is either a declared service or is named as unclaimed ($SCOPE133)"
fi
}
