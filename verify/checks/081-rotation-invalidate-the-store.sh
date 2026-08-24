# title: rotation: invalidate the store (end of the silent no-op) (W-09/R5)
# origin: verify-static.sh (v2) ══ 81
check() {
# The bug: gen_or_restore RESTORES the old .enc → re-running the phase does
# NOT rotate (a silent no-op for 11 of 14). Fix: aegis-rotate removes the .enc
# so the phase regenerates it. Invariants:
D81=""
RT="$LIBEXEC/aegis-rotate"
CL="$P/docs/protocols/rotation-checklist.md"
if [[ -f "$RT" ]]; then
    bash -n "$RT" 2>/dev/null || D81="$D81 aegis-rotate.sh does not parse;"
    [[ -x "$RT" ]] || D81="$D81 aegis-rotate.sh not executable;"
    # it invalidates by removing the .enc from the store
    grep -Eq 'rm -f "\$enc"' "$RT" || D81="$D81 does not invalidate the store's .enc (it would not rotate);"
    grep -q 'STATE_SECRETS'     "$RT" || D81="$D81 does not operate on the store;"
    # dry-run by default: it only acts with --yes
    grep -q 'YES=0'   "$RT" || D81="$D81 not dry-run by default (dangerous);"
    grep -q -- '--yes' "$RT" || D81="$D81 no --yes gate;"
    # it refuses irreducibles (cosign invalidates signatures; age is the root)
    grep -q 'IRREDUCIBLE' "$RT" || D81="$D81 no irreducibles guard;"
    grep -q 'cosign'      "$RT" || D81="$D81 does not protect cosign (regenerating it breaks phase 80);"
else
    D81="$D81 init/aegis-rotate.sh missing;"
fi
# the doc and the code do not diverge: the checklist MUST point at Step 0
grep -q 'aegis-rotate' "$CL" 2>/dev/null \
    || D81="$D81 rotation-checklist.md does not document Step 0 (invalidate the store) — the no-op comes back;"
if [[ -n "$D81" ]]; then fail "rotation-store:$D81"
else pass "aegis-rotate: invalidates the store (dry-run+--yes), refuses irreducibles, checklist with Step 0"; fi
}
