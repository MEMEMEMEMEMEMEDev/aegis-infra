# title: the jobs the ci command fires are the ones the job-dsl declares, not a list written by hand
# origin: new in v3 — 2026-09-01, the day «engine-gpu is not a job of the chain» was said about a job this artifact creates
check() {
# MEASURED. `aegis ci build engine-gpu` answered:
#
#   aegis ci: «engine-gpu» is not a job of the chain: mirror-images
#   ci-images base-images image-watch
#
# about a job the SAME artifact declares, seeds and builds. That list
# was an array in libexec/aegis-ci. Jenkins had twelve jobs that
# morning — the four of the chain, three AI lanes, and five
# multibranches, four of them derived by `aegis org apply` — and eight
# of them could not be fired with the product that created them. The
# operator called lib/jenkins.sh by hand instead.
#
# The class is not «the AI lanes were forgotten». It is A LIST WRITTEN
# BY HAND BESIDE AN ARTIFACT THAT GROWS, and it appeared four times in
# one day: a list of consumers missing two new phases, a one-level glob
# blind to nested lanes, a list of jobs without the AI ones, this. The
# fix is always the same shape — derive the set from the artifact that
# defines it — and so is the check: derive the same set here and demand
# the command can fire every member of it.
#
# WHY THE CHECK DRIVES THE COMMAND instead of reading it. Any static
# rule can be satisfied by writing today's twelve names out by hand,
# which is the state this exists to forbid. So the scan builds a
# synthetic instance whose job-dsl declares two jobs INVENTED one
# second earlier and asks the command about them. A list cannot contain
# a name that did not exist when it was typed. Nothing of the operator's
# cluster is touched: a kubectl that answers nothing to everything sits
# on the PATH, so the walk stops at «could not evaluate» — which is
# precisely the answer that proves the name was accepted.
#
# What is NOT derived, and says so: the ORDER of the supply chain
# (mirror-images -> ci-images -> base-images -> image-watch). The
# job-dsl declares four items with no relation between them; the
# relation is the chain, and firing it out of order does not fail
# loudly, it builds on yesterday's mirror and says SUCCESS. So the order
# stays written down — and every name in it is checked against the
# job-dsl, so an order cannot outlive its jobs.
VALUES="$SEED/platform/k8s/base/platform/jenkins/values.yaml"
CI="$LIBEXEC/aegis-ci"
[[ -f "$VALUES" ]] || { fail "the job-dsl is not there: $VALUES"; return; }
[[ -f "$CI" ]] || { fail "libexec/aegis-ci is not there: $CI"; return; }

D177=""
# The scan is python and in its own file: a shell scan that dies
# quietly turns a check green (check 166), and aegis-ci documents this
# very bug in its header — job names included — so the read is over
# code with the comments stripped (checks 161, 163, 165, 167, 168).
if ! OUT="$(python3 "$AEGIS_ROOT/verify/checks/177.py" "$AEGIS_ROOT" "$VALUES" 2>/dev/null)"; then
    D177="$D177 the scan itself failed and this check measured nothing;"
elif [[ -n "$OUT" ]]; then
    while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        D177="$D177 $hit;"
    done <<< "$OUT"
fi
N="$(python3 "$AEGIS_ROOT/verify/checks/177.py" "$AEGIS_ROOT" "$VALUES" 2>&1 >/dev/null | awk '/__COUNT__/{print $2" jobs declared by the seed'\''s job-dsl · "$3" of them ordered as the supply chain"}')"

printf '    %s\n' "${N:-the job-dsl could not be counted}"
if [[ -n "$D177" ]]; then fail "the ci command does not fire what the job-dsl declares:$D177"
else pass "every job the job-dsl declares — including two invented for this run — is listed and accepted by the ci command, a multibranch is addressed by the branch Jenkins builds, the refusal of an unknown name offers the derived list, and the only thing written by hand is the chain's order"; fi
}
