# title: asíncrono espera con poll; el orden respeta la causa (clase D)
# origen: verify-static.sh (v2) ══ 67
check() {
D67=""
NC80="$(sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/80-supply-chain.sh" | nc)"
echo "$NC80" | grep '"policy-ready"' | grep -q 'poll' \
    || D67="$D67 policy-ready single-shot sobre un paso asíncrono;"
echo "$NC80" | grep '"webhooks-scopeados"' | grep -q 'poll' \
    || D67="$D67 webhooks-scopeados single-shot;"
L_SYNC="$(grep -n 'argo_sync kyverno-policies' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
L_WH="$(grep -n '"webhooks-scopeados"' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
if [[ -n "$L_SYNC" && -n "$L_WH" ]] && (( L_WH < L_SYNC )); then
    D67="$D67 webhooks-scopeados corre ANTES del sync de la policy que lo genera (efecto antes que causa);"
fi
sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/50-jenkins.sh" \
  | nc | grep '"job-ci-images-existe"' | grep -q 'retry_net' \
    || D67="$D67 job-ci-images-existe single-shot (el seed del job-dsl es async al boot);"
sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/35-gitops.sh" \
  | nc | grep '"edge-responde"' | grep -q 'poll' \
    || D67="$D67 edge-responde con ~30s para una propagación DNS de minutos;"
NC50="$(nc "$PHASES/50-jenkins.sh")"
echo "$NC50" | grep -q 'wait_rollout jenkins-system sts/jenkins' \
    || D67="$D67 el boot de jenkins (el paso más lento legítimo) sin wait_rollout con evidencia;"
# 60: el job main se espera ANTES de capturar NEXT_MB (indexing async):
L_IDX="$(grep -n '"job-main-indexado"' "$PHASES/60-webhook.sh" | head -1 | cut -d: -f1)"
L_NEXT="$(grep -n 'NEXT_MB=' "$PHASES/60-webhook.sh" | head -1 | cut -d: -f1)"
if [[ -z "$L_IDX" || -z "$L_NEXT" ]] || (( L_IDX > L_NEXT )); then
    D67="$D67 la 60 captura NEXT_MB sin esperar el branch indexing;"
fi
nc "$PHASES/60-webhook.sh" | grep -q 'deliveries/\$did/attempts' \
    || D67="$D67 la espera de delivery no re-entrega (GitHub no reintenta solo un 530 del tunnel);"
if [[ -n "$D67" ]]; then fail "asincronía/orden:$D67"
else pass "todo paso asíncrono con poll+evidencia; webhook re-entregado; efecto después de su causa"; fi
}
