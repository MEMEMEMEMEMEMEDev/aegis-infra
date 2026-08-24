# titulo: probes del gate final compliant + deny CITANDO la policy (CR-3/CR-4 #14)
# origen: verify-static.sh (v2) ══ 50
check() {
# CR-4: un pod pelado en org-canary lo rechazan PSS/quota AUNQUE
# Kyverno no exista → el negativo debe ser PSS/quota-compliant y el
# assert va sobre el MENSAJE del deny. CR-3: el scope-probe sin
# limits lo rechaza la quota de jenkins-system ANTES de Kyverno:
D50=""
# los kubectl run van con continuaciones \ — unirlas ANTES de grepear
# (line-based vería la primera línea "sin --overrides" en falso):
F80_J="$(sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$FASES/80-supply-chain.sh" \
    | nc)"
echo "$F80_J" | grep -q 'grep -q .require-aegis-signature. <<<' \
    || D50="$D50 el negativo no asserta el mensaje del deny (falso verde CR-4);"
echo "$F80_J" | grep -q 'PROBE_SC=' && echo "$F80_J" | grep -q 'runAsNonRoot' \
    || D50="$D50 el probe negativo sin securityContext restricted;"
echo "$F80_J" | grep -q 'PROBE_RES=' && echo "$F80_J" | grep -q '"limits"' \
    || D50="$D50 probes sin resources/limits (la quota los rechaza por la razón equivocada);"
# ambos kubectl run de probes llevan --overrides:
BAD50="$(echo "$F80_J" | grep -E 'kubectl .*run (unsigned-probe|scope-probe)' \
    | grep -v -- '--overrides' || true)"
[[ -n "$BAD50" ]] && D50="$D50 probe sin --overrides:"$'\n'"$BAD50"
if [[ -n "$D50" ]]; then fail "probes del gate final:$D50"
else pass "negativo compliant + assert sobre el deny (cita la policy); scope con limits"; fi
}
