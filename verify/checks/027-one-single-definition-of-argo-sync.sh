# title: ONE single definition of argo_sync (bug C — anti-drift)
# origin: verify-static.sh (v2) ══ 27
check() {
# Run #8: 5 phases defined their own local argo_sync (patch + health
# wait) → the health-vs-operationState race lived replicated in all of
# them. The fix for bug C is the CANONICAL definition in common.sh (it
# waits for the TERMINAL phase of the new operation); a new local def
# would cover it up silently:
SYNC_LOCAL="$(grep -rln '^argo_sync()' "$PHASES/" || true)"
SYNC_COMMON="$(grep -c '^argo_sync()' "$LIBS/common.sh" || true)"
if [[ -n "$SYNC_LOCAL" ]]; then
    fail "argo_sync REDEFINED locally (covers up the bug C fix):"$'\n'"$SYNC_LOCAL"
elif [[ "$SYNC_COMMON" != 1 ]]; then
    fail "canonical argo_sync absent/duplicated in common.sh ($SYNC_COMMON)"
else
    pass "argo_sync: one single definition (common.sh, terminal-phase-aware)"
fi
}
