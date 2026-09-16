# title: the console writes files in this instance, a contract or a plan, or nothing at all
# origin: new in v3 — 2026-09-12, the first screen of the console that writes (plan/15 §12)
check() {
# THE CONSOLE READS. One screen of it now writes, and that is the moment
# a tool stops being safe by construction and becomes safe by promise.
# The promise is small on purpose and it is `aegis org`'s own:
#
#   it writes ONE contract into orgs/, it does not commit, it does not
#   push, it does not apply, and it does not touch the cluster.
#
# That is what makes a file in a working tree harmless: ArgoCD reads the
# REMOTE, so nothing runs until somebody commits. Every clause of that
# sentence can be broken by a change that looks like an improvement, and
# none of them would fail — the console would go on working, and the
# only difference would be what it had already done by the time anybody
# noticed.
#
# So the real function is run against a real tree and the WHOLE TREE is
# compared before and after: not «did it write the right file» but what
# else did it touch. Then the source is read for the other half, and it
# is read as CODE — the first version of this check grepped for the
# words and went red on its own comment, which is the mistake this
# repository has filed six times.
D099=""
[[ -f "$LIBEXEC/aegis-console" ]] || { skip "there is no console: this check has no subject"; return; }
grep -q 'def write_contract' <<<"$(nc "$LIBEXEC/aegis-console")" || { skip "the console does not write yet: this check has no subject"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/099.py" ]] || { fail "check 099 has no sidecar: the write was never exercised"; return; }

OUT099="$(python3 "$AEGIS_ROOT/verify/checks/099.py" "$AEGIS_ROOT" 2>&1)"
RC099=$?
if (( RC099 != 0 )); then
    fail "the exercise of check 099 itself failed (rc $RC099) and the write was never tried: $OUT099"
    return
fi
SCOPE099=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE099="${hit#SCOPE: }" ;;
        *)       D099="$D099 $hit;" ;;
    esac
done <<< "$OUT099"

printf '    %s\n' "${SCOPE099:-the scope was not reported}"
if [[ -n "$D099" ]]; then
    fail "the console does more than write one contract:$D099"
else
    pass "one contract lands in orgs/, nothing else is touched, an existing one is not written over, and a refused one leaves nothing behind ($SCOPE099)"
fi
}
