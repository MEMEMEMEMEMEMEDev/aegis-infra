# title: gates that cannot fail (tautologies)
# origin: verify-static.sh (v2) ══ 8
check() {
# heuristic: the line/command of a gate must not end up swallowing the
# result (|| true, ; true) — a gate like that is not a gate.
TAUT="$(grep -rn 'gate ' "$PHASES" "$AEGIS_ROOT/init/lib" \
    | grep -E '\|\|\s*true|;\s*true\s*"?$' || true)"
if [[ -n "$TAUT" ]]; then fail "tautological gates:"$'\n'"$TAUT"
else pass "no tautological gates"; fi
}
