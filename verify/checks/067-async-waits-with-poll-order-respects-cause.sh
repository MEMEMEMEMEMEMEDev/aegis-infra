# title: asynchronous work waits with poll; the order respects the cause (class D)
# origin: verify-static.sh (v2) ══ 67
check() {
D67=""
NC80="$(sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/80-supply-chain.sh" | nc)"
echo "$NC80" | grep '"policy-ready"' | grep -q 'poll' \
    || D67="$D67 policy-ready single-shot over an asynchronous step;"
echo "$NC80" | grep '"webhooks-scopeados"' | grep -q 'poll' \
    || D67="$D67 webhooks-scopeados single-shot;"
L_SYNC="$(grep -n 'argo_sync kyverno-policies' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
L_WH="$(grep -n '"webhooks-scopeados"' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
if [[ -n "$L_SYNC" && -n "$L_WH" ]] && (( L_WH < L_SYNC )); then
    D67="$D67 webhooks-scopeados runs BEFORE the sync of the policy that generates it (effect before cause);"
fi
sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/50-jenkins.sh" \
  | nc | grep '"job-ci-images-existe"' | grep -q 'retry_net' \
    || D67="$D67 job-ci-images-existe single-shot (the job-dsl seeding is async to the boot);"
sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/35-gitops.sh" \
  | nc | grep '"edge-responde"' | grep -q 'poll' \
    || D67="$D67 edge-responde with ~30s for a DNS propagation that takes minutes;"
NC50="$(nc "$PHASES/50-jenkins.sh")"
echo "$NC50" | grep -q 'wait_rollout jenkins-system sts/jenkins' \
    || D67="$D67 jenkins' boot (the slowest legitimate step) without wait_rollout and evidence;"
# 60: the main job is waited for BEFORE capturing NEXT_MB (async indexing):
L_IDX="$(grep -n '"job-main-indexado"' "$PHASES/60-webhook.sh" | head -1 | cut -d: -f1)"
L_NEXT="$(grep -n 'NEXT_MB=' "$PHASES/60-webhook.sh" | head -1 | cut -d: -f1)"
if [[ -z "$L_IDX" || -z "$L_NEXT" ]] || (( L_IDX > L_NEXT )); then
    D67="$D67 phase 60 captures NEXT_MB without waiting for the branch indexing;"
fi
nc "$PHASES/60-webhook.sh" | grep -q 'deliveries/\$did/attempts' \
    || D67="$D67 the delivery wait does not re-deliver (GitHub does not retry a 530 from the tunnel on its own);"
if [[ -n "$D67" ]]; then fail "asynchrony/order:$D67"
else pass "every asynchronous step with poll+evidence; webhook re-delivered; effect after its cause"; fi
}
