# title: --from/--only with a nonexistent phase = hard error (run #10)
# origin: verify-static.sh (v2) ══ 32
check() {
# a name matching no phase made the whole loop skip and report
# "complete" — a false 'all done'. The REAL validation is demanded
# (calls to phase_exists over both flags, non-comment), not the
# mention in a comment:
# session 21 (P3 of the audit): the validation went up from existence
# to UNIQUENESS — phase_check_unique also dies on an AMBIGUOUS prefix
# ('--from 1' matched 10/12/15 and started at 10 with no warning):
INIT_NC="$(nc "$LIBEXEC/aegis-init")"
if echo "$INIT_NC" | grep -q 'phase_check_unique --from "\$FROM_PHASE"' \
   && echo "$INIT_NC" | grep -q 'phase_check_unique --only "\$ONLY_PHASE"' \
   && echo "$INIT_NC" | grep -q 'unknown phase' \
   && echo "$INIT_NC" | grep -q 'AMBIGUOUS'; then
    pass "--from and --only validated against PHASES: nonexistent AND ambiguous both abort"
else
    fail "aegis-init.sh does NOT validate --from/--only (existence + uniqueness) against the real phases"
fi
}
