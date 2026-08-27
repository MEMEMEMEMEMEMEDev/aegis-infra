# title: Kyverno: CA with a post-injection restart + deny-by-default (W-04)
# origin: verify-static.sh (v2) ══ 68
check() {
# P1.1 (confirmed live): subPath does NOT refresh — without a restart
# the controllers keep the old CA → x509 → fail-closed deny.
D68=""
NC80B="$(nc "$PHASES/80-supply-chain.sh")"
echo "$NC80B" | grep -q 'CA_INJECTED_THIS_RUN' \
    || D68="$D68 phase 80 does not distinguish whether the CA was injected on THIS run;"
echo "$NC80B" | grep -q 'rollout restart' \
    || D68="$D68 no rollout restart after the injection (subPath freezes the old CA in memory);"
# 2026-08-27, second init over a host that carried an instance: the
# placeholder was gone, the file held the previous cluster's CA, and
# Kyverno fell back to plain HTTP against the registry. Presence is not
# identity — phase 80 compares the injected CA with the live one:
echo "$NC80B" | grep -q 'pem_stale "$KYV"' \
    || D68="$D68 phase 80 does not compare the injected CA with the live one (a previous cluster's CA stays forever);"
echo "$NC80B" | grep -q 'ca-en-kyverno-es-la-viva' \
    || D68="$D68 phase 80 has no gate that the CA in kyverno's values IS the live one;"
# W-04 / R1 / PLAT-03 — DENY-BY-DEFAULT: imageReferences is '*' (every
# pod signed), NOT an allowlist by name. Enumerating shapes was paid for
# (P1.2); the invariant is that the allowlist by name does NOT exist:
POL68="$P/k8s/base/kyverno-policies/clusterpolicy-require-aegis-signature.yaml"
POLIR="$(nc "$POL68")"
echo "$POLIR" | grep -Eq '^\s*-\s*"\*"' \
    || D68="$D68 imageReferences is not '*' (deny-by-default: every pod signed, not an allowlist by name);"
echo "$POLIR" | grep -q 'hello-aegis\*' \
    && D68="$D68 the policy still has the allowlist by name (hello-aegis*) — that is the P1.2 bypass;"
echo "$POLIR" | grep -q 'failureAction: Enforce' \
    || D68="$D68 the rule is not Enforce;"
# the runtime gate that PROVES deny-by-default exists (unsigned nginx):
echo "$NC80B" | grep -q 'negativo-deny-by-default' \
    || D68="$D68 the negativo-deny-by-default gate is missing from phase 80;"
if [[ -n "$D68" ]]; then fail "kyverno:$D68"
else pass "restart after the CA; imageReferences '*' deny-by-default (no allowlist by name); negative nginx gate"; fi
}
