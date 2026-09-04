# title: Kyverno's defaults are ignored wherever the artifact ships a policy
# origin: new in v3 — 2026-09-04, measured on the instance from the clean install
check() {
# MEASURED 2026-09-04, two days after the definitive installation.
#
# `org-portafolio` had been OutOfSync since it was born. Every one of
# its resources was Healthy, every sync ended Succeeded, and ArgoCD
# re-applied it every five minutes forever. The whole difference, read
# out of ArgoCD's own cached comparison, was one field:
#
#     .spec.rules[].skipBackgroundRequests
#
# which Kyverno's webhook writes into every rule and which the manifest,
# correctly, does not declare.
#
# The instructive part is not the field. It is that THE ARTIFACT HAD
# ALREADY PAID FOR THIS LESSON: the `kyverno-policies` App carries an
# ignoreDifferences list for exactly this family of defaults, written
# after the same failure on ClusterPolicy. When `tamano` introduced a
# namespaced Policy on 2026-08-29, nobody carried the list across, and
# the same hole reopened one floor down.
#
# A cure that only ever gets applied where it was first needed is not a
# cure; it is an anecdote. So the subject here is DERIVED: every Kyverno
# policy kind the artifact ships or generates must have its defaults
# ignored somewhere, all such lists must be the SAME list, and the
# ignore has to reach the apply and not only the diff — without
# RespectIgnoreDifferences ArgoCD keeps sending the very fields it
# claims to ignore, and nothing closes.
#
# And the cost of not having this is worse than a red light. A light
# that is always red stops being read: `aegis check` reported "drifted
# apps" for two days and the true answer was "nothing has drifted".
D186=""
GEN="$AEGIS_ROOT/lib/aegis/org.py"
[[ -f "$GEN" ]] || { skip "the artifact has no organization generator: this check has no subject"; return; }

OUT="$(python3 "$AEGIS_ROOT/verify/checks/186.py" "$AEGIS_ROOT" 2>/dev/null)"
RC=$?
if (( RC != 0 )); then
    fail "the scan of check 186 itself failed (rc $RC) and this check measured nothing about the ignore lists"
    return
fi
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    D186="$D186 $hit;"
done <<< "$OUT"

N="$(python3 "$AEGIS_ROOT/verify/checks/186.py" "$AEGIS_ROOT" 2>&1 >/dev/null | awk '/__COUNT__/{print $2}')"
printf '    %s facts asked of every kyverno.io ignore list in the artifact, with the prose around them stripped\n' "${N:-0}"
if [[ -n "$D186" ]]; then fail "a Kyverno policy can stay OutOfSync forever with nothing wrong with it:$D186"
else pass "every Kyverno policy kind the artifact ships has its defaults ignored, with one and the same list, respected at apply time, still covering the default measured to break it, and without ignoring a whole subtree"; fi
}
