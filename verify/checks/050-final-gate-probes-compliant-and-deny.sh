# title: final gate probes compliant + deny CITING the policy (CR-3/CR-4 #14)
# origin: verify-static.sh (v2) ══ 50
check() {
# CR-4: a bare pod in org-canary is rejected by PSS/quota EVEN IF
# Kyverno does not exist → the negative must be PSS/quota-compliant and
# the assert goes over the MESSAGE of the deny. CR-3: the scope-probe
# without limits is rejected by the jenkins-system quota BEFORE Kyverno:
D50=""
# the kubectl runs come with \ continuations — join them BEFORE
# grepping (line-based would falsely see the first line "without
# --overrides"):
F80_J="$(sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/80-supply-chain.sh" \
    | nc)"
echo "$F80_J" | grep -q 'grep -q .require-aegis-signature. <<<' \
    || D50="$D50 the negative does not assert the message of the deny (false green CR-4);"
echo "$F80_J" | grep -q 'PROBE_SC=' && echo "$F80_J" | grep -q 'runAsNonRoot' \
    || D50="$D50 the negative probe has no restricted securityContext;"
echo "$F80_J" | grep -q 'PROBE_RES=' && echo "$F80_J" | grep -q '"limits"' \
    || D50="$D50 probes without resources/limits (the quota rejects them for the wrong reason);"
# both kubectl runs of the probes carry --overrides:
BAD50="$(echo "$F80_J" | grep -E 'kubectl .*run (unsigned-probe|scope-probe)' \
    | grep -v -- '--overrides' || true)"
[[ -n "$BAD50" ]] && D50="$D50 probe without --overrides:"$'\n'"$BAD50"
if [[ -n "$D50" ]]; then fail "final gate probes:$D50"
else pass "compliant negative + assert over the deny (it cites the policy); scope with limits"; fi
}
