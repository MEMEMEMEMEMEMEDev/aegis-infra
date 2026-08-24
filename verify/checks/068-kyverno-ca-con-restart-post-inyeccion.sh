# title: Kyverno: CA con restart post-inyección + deny-by-default (W-04)
# origen: verify-static.sh (v2) ══ 68
check() {
# P1.1 (confirmado en vivo): subPath NO refresca — sin restart, los
# controllers quedan con el CA viejo → x509 → deny fail-closed.
D68=""
NC80B="$(nc "$PHASES/80-supply-chain.sh")"
echo "$NC80B" | grep -q 'CA_INYECTADO_ESTA_CORRIDA' \
    || D68="$D68 la 80 no distingue si el CA se inyectó en ESTA corrida;"
echo "$NC80B" | grep -q 'rollout restart' \
    || D68="$D68 sin rollout restart post-inyección (subPath congela el CA viejo en memoria);"
# W-04 / R1 / PLAT-03 — DENY-BY-DEFAULT: imageReferences es '*' (todo
# pod firmado), NO allowlist por nombre. Enumerar formas se pagó (P1.2);
# el invariante es que NO exista la allowlist por nombre:
POL68="$P/k8s/base/kyverno-policies/clusterpolicy-require-aegis-signature.yaml"
POLIR="$(nc "$POL68")"
echo "$POLIR" | grep -Eq '^\s*-\s*"\*"' \
    || D68="$D68 imageReferences no es '*' (deny-by-default: todo pod firmado, no allowlist por nombre);"
echo "$POLIR" | grep -q 'hello-aegis\*' \
    && D68="$D68 la policy sigue con allowlist por nombre (hello-aegis*) — es el bypass P1.2;"
echo "$POLIR" | grep -q 'failureAction: Enforce' \
    || D68="$D68 la regla no es Enforce;"
# el gate de runtime que PRUEBA deny-by-default existe (nginx sin firma):
echo "$NC80B" | grep -q 'negativo-deny-by-default' \
    || D68="$D68 falta el gate negativo-deny-by-default en la fase 80;"
if [[ -n "$D68" ]]; then fail "kyverno:$D68"
else pass "restart post-CA; imageReferences '*' deny-by-default (no allowlist por nombre); gate negativo nginx"; fi
}
