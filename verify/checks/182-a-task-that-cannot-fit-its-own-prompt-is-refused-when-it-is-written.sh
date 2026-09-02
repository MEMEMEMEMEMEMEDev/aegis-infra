# title: a task that cannot fit its own prompt is refused where the contract is written
# origin: new in v3 — 2026-09-02, after a task ran for months with less context than its own prompt
check() {
# MEASURED IN PRODUCTION 2026-09-02, against the engine's own tokeniser.
#
# `portafolio.chat.guia` ran with the ceilings of its class: 1500
# context tokens and 800 input characters. Its prompt alone tokenised to
# 1509. The task could not fit its own prompt, without a single
# character from the visitor, and it was allowed to exist that way by
# the contract, by `aegis org apply` and by every gate.
#
# Two things made it survive. First, nothing measures a prompt against
# the ceiling that has to hold it: the numbers are hand tuning and the
# prompt is content, they live in different files and nobody multiplied
# them together. Second, ANOTHER defect was hiding it — while the CPU
# lane was dead the assistant's backend fell back to its no-memory
# branch and sent the bare question, which fitted, so the ceiling was
# never actually tested. Fixing the lane is what surfaced the 400 that
# had been latent all along. A defect that hides another is the reason
# to check the arithmetic instead of the symptom.
#
# The rule is EXERCISED here, not read. A `raise` that no path reaches
# passes any grep, so this check imports the product's own registry
# generator and calls it over a toy platform:
#
#   1. a prompt that fits is accepted — a rule that cries wolf on the
#      ordinary case is a rule somebody deletes;
#   2. a prompt larger than the whole window is refused, naming the
#      number to change;
#   3. and raising that number in ai/tasks.yaml, which is exactly what
#      the refusal tells the operator to do, LIFTS it. A refusal whose
#      escape hatch does not work is worse than silence: it spends the
#      reader's trust as well as their time.
#
# The estimate is deliberately generous — four characters per token,
# where Spanish measured 3.38 against the engine — so it undercounts
# tokens and refuses only what is certainly impossible.
D182=""
[[ -f "$AEGIS_ROOT/lib/aegis/org.py" ]] || { skip "there is no lib/aegis/org.py: this check has no generator to exercise"; return; }

OUT="$(python3 "$AEGIS_ROOT/verify/checks/182.py" "$AEGIS_ROOT" 2>/dev/null)"
RC=$?
if (( RC == 3 )); then
    skip "the seed ships no ai/tasks.yaml or ai/routes.yaml, so no platform could be built to exercise the rule: this is «I could not look», not «it is fine»"
    return
fi
if (( RC != 0 )); then
    fail "the scan of check 182 itself failed (rc $RC) and this check measured nothing about the rule"
    return
fi
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    D182="$D182 $hit;"
done <<< "$OUT"

N="$(python3 "$AEGIS_ROOT/verify/checks/182.py" "$AEGIS_ROOT" 2>&1 >/dev/null | awk '/__COUNT__/{print $2}')"
printf '    %s cases run against the real registry generator\n' "${N:-0}"
if [[ -n "$D182" ]]; then fail "a task can be written that cannot fit its own prompt:$D182"
else pass "the generator refuses a task whose prompt cannot fit its context ceiling, names the number to change, and that number actually lifts the refusal"; fi
}
