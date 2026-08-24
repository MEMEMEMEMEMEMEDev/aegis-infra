# title: gates that wait SPEAK when they fail (H7 #13)
# origin: verify-static.sh (v2) ══ 47
check() {
D47=""
# $F70_NC used to be left behind by check 46: the second of v2's four
# couplings. `--only 47` in that file compared against an empty
# variable and passed green without looking at anything.
F70_NC="$(nc "$PHASES/70-deploy-auto.sh")"
grep -q '^gate_diag()' "$LIBS/common.sh" || D47="$D47 gate_diag missing;"
# iu-cr-vivo and iu-write-back-commit went away with the Image Updater
# (#59); the gate that replaces them is pipeline-escribio-el-digest.
for g in canary-corriendo anti-loop-build-salteado pipeline-escribio-el-digest; do
    echo "$F70_NC" | grep -q "gate_diag \"$g\"" || D47="$D47 $g without diagnosis;"
done
# the timeout of argo_secrets_gate exposes operationState.message:
ASG_BODY="$(body_of argo_secrets_gate "$LIBS/common.sh" \
    | nc)"
echo "$ASG_BODY" | grep -q 'operationState.message' \
    || D47="$D47 argo_secrets_gate dies mute on timeout;"
if [[ -n "$D47" ]]; then fail "mute timeouts:$D47"
else pass "critical gates with evidence when they fail (events/describe/operationState/console)"; fi
}
