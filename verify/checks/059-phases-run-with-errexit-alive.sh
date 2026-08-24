# title: phases run with errexit ALIVE (F-A #15 — the set -e mystery)
# origin: verify-static.sh (v2) ══ 59
check() {
# `if ( source phase )` puts the phase in a condition context → bash
# IGNORES errexit inside and the internal set -e is IMPOTENT
# (documented semantics) → NO non-gate failure ever cut a run (#9 the
# fallen push, #15 argo_sync Error followed by a green gate). The
# orchestrator must run the phase as a PLAIN command and capture the rc
# with the parent's errexit switched off:
D59=""
ORQ="$LIBEXEC/aegis-init"
nc "$ORQ" | grep -q 'if ( source' \
    && D59="$D59 the phase runs in an if condition (errexit dead inside);"
nc "$ORQ" | grep -qE '\( source "\$p" \)( \|\||\s*&&)' \
    && D59="$D59 the phase's subshell is in a ||/&& list (same ignored context);"
ORQ_NC="$(nc "$ORQ")"
echo "$ORQ_NC" | grep -q '( source "$p" )' \
    || D59="$D59 cannot find the phase's plain subshell;"
echo "$ORQ_NC" | grep -B2 '( source "$p" )' | grep -q 'set +e' \
    || D59="$D59 missing the parent's set +e before the subshell (with the parent's -e, the rc is never captured);"
echo "$ORQ_NC" | grep -A1 '( source "$p" )' | grep -q '_phase_rc=\$?' \
    || D59="$D59 the phase's rc is not captured;"
if [[ -n "$D59" ]]; then fail "phase errexit:$D59"
else pass "phases as a plain command + captured rc — the internal set -e is finally EFFECTIVE"; fi
}
