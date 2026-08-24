# title: gates that cannot fail (tautologies)
# origin: verify-static.sh (v2) ══ 8
check() {
# heuristic: the line/command of a gate must not end up swallowing the
# result (|| true, ; true) — a gate like that is not a gate.
# CORRECTED on 2026-08-24: the second path was `init/lib`, which does
# not exist in v3 — the libs moved to `lib/` (02 §1). grep warned and
# the trailing `|| true` swallowed it, so a tautological gate written
# in a lib was never seen. lib/secrets.sh alone calls `gate` twice.
TAUT="$(grep -rn 'gate ' "$PHASES" "$LIBS" \
    | grep -E '\|\|\s*true|;\s*true\s*"?$' || true)"
if [[ -n "$TAUT" ]]; then fail "tautological gates:"$'\n'"$TAUT"
else pass "no tautological gates"; fi
}
