# title: builds awaited by NUMBER, not lastBuild (race #9)
# origin: verify-static.sh (v2) ══ 29
check() {
# after a trigger, lastBuild is still the PREVIOUS one for ~5-10s:
# reading it = bug class C. EVERY jenkins_wait_build in the phases must
# carry the 3rd arg (captured with jenkins_next_build BEFORE the
# trigger), and no phase may query lastBuild directly:
W29=""
# a) jenkins_wait_build with only 2 args (job + timeout, no build):
# the comment filter over grep -rn output = the file:line: prefix (the
# original ^\s*# NEVER filtered — a comment in phase 60 uncovered it in
# session 19; same pattern as 29b):
BAD_WAIT="$(grep -rn 'jenkins_wait_build [a-z]' "$PHASES/" \
    | nc_hits \
    | grep -vE 'jenkins_wait_build [^ ]+ [0-9]+ ' || true)"
[[ -n "$BAD_WAIT" ]] && W29="$W29 wait with no build_n:"$'\n'"$BAD_WAIT"
# b) lastBuild directly in the phases — the real USE is a path
#    component of the API (/lastBuild), not the word in a trailing
#    comment (mention ≠ use — the tooth revealed it):
BAD_LAST="$(grep -rn '/lastBuild' "$PHASES/" \
    | nc_hits || true)"
[[ -n "$BAD_LAST" ]] && W29="$W29 lastBuild directly:"$'\n'"$BAD_LAST"
if [[ -n "$W29" ]]; then fail "lastBuild race:$W29"
else pass "every build is awaited by its specific number (jenkins_next_build)"; fi
}
