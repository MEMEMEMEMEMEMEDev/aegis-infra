# title: builds SPEAK on failure and retry ONLY on network (F-C/F-D #15)
# origin: verify-static.sh (v2) ══ 60
check() {
D60=""
JWB="$(body_of jenkins_wait_build "$LIBS/jenkins.sh")"
# the console goes on the FAILURE path **AND** on the timeout (the
# tooth revealed that a single grep was satisfied by the timeout alone):
(( "$(echo "$JWB" | grep -c 'consoleText')" >= 2 )) \
    || D60="$D60 jenkins_wait_build without console on FAILURE and timeout (two mute FAILUREs in #15);"
JBR="$(body_of jenkins_build_retry "$LIBS/jenkins.sh")"
[[ -n "$JBR" ]] || D60="$D60 jenkins_build_retry missing;"
echo "$JBR" | grep -q 'AEGIS_NET_SIGS' \
    || D60="$D60 the retry does not discriminate by network signature (it would retry REAL failures);"
echo "$JBR" | grep -q 'jenkins_next_build' \
    || D60="$D60 the retry does not capture next before the POST (race #9);"
nc "$LIBS/common.sh" | grep -q '^AEGIS_NET_SIGS=' \
    || D60="$D60 AEGIS_NET_SIGS missing from common.sh;"
nc "$PHASES/50-jenkins.sh" | grep -q 'jenkins_build_retry ci-images' \
    || D60="$D60 phase 50 does not use jenkins_build_retry for ci-images;"
if [[ -n "$D60" ]]; then fail "builds:$D60"
else pass "FAILURE prints the console; retry ONLY with a network signature (a real failure cuts immediately)"; fi
}
