# title: an organization nobody could look at is not an empty organization
# origin: new in v3 — 2026-09-12, the screen of ONE organization (plan/15 §11)
check() {
# THE PRODUCT'S THESIS, on the screen a person will spend the most time
# on. `aegis tenant show` answers «what does this organization actually
# have running», and three answers look alike on a page:
#
#   seven services running    nothing to do
#   seven services absent     the namespace is gone — act now
#   nobody could ask          the instrument never arrived
#
# The last two are the dangerous pair. A command that drew seven absent
# services because kubectl reached nothing would send the operator to
# rebuild an organization that was serving traffic the whole time, and
# every figure on that screen would be TRUE of the document in front of
# them. That is the failure this repo filed on 2026-09-10 and it has a
# name: a coherent and false measurement.
#
# Behavioural, on a copy in tmpfs, with a stub kubectl: the command
# shells out to kubectl, so a kubectl that answers from a script is the
# only way to put three different clusters in front of it inside
# `aegis verify`. Nothing is created, nothing is contacted.
D121=""
[[ -f "$LIBEXEC/aegis-tenant" ]] || { skip "there is no \`aegis tenant\`: this check has no subject"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/121.py" ]] || { fail "check 121 has no sidecar: the exercise cannot run"; return; }

OUT121="$(python3 "$AEGIS_ROOT/verify/checks/121.py" "$AEGIS_ROOT" 2>&1)"
RC121=$?
if (( RC121 != 0 )); then
    fail "the exercise of check 121 itself failed (rc $RC121) and the three answers were never compared: $OUT121"
    return
fi
SCOPE121=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE121="${hit#SCOPE: }" ;;
        *)       D121="$D121 $hit;" ;;
    esac
done <<< "$OUT121"

printf '    %s\n' "${SCOPE121:-the scope was not reported}"
if [[ -n "$D121" ]]; then
    fail "an organization's screen confuses «I could not look» with «there is nothing there»:$D121"
else
    pass "blind, absent and healthy come out as three different answers, with three different rc ($SCOPE121)"
fi
}
