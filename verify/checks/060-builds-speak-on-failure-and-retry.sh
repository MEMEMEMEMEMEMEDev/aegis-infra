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
# 2026-08-27, first clean instance: phase 80.7 fired base-images (a job
# WITH parameters) through /build, Jenkins refused it in its own log
# only, and the wait sat 45 min on a build that never existed. The
# trigger goes through jenkins_fire (the endpoint the job accepts, the
# POST's failure said out loud) and a build that does not appear is
# reported long before the build's timeout:
echo "$JBR" | grep -q 'jenkins_fire "$job"' \
    || D60="$D60 the retry does not fire through jenkins_fire (a parameterized job refuses /build, silently);"
JF="$(body_of jenkins_fire "$LIBS/jenkins.sh")"
echo "$JF" | grep -q 'buildWithParameters' && echo "$JF" | grep -q 'jenkins_job_parameterized' \
    || D60="$D60 jenkins_fire does not pick buildWithParameters by asking the job whether it is parameterized;"
{ echo "$JF" | grep -q 'jenkins_post "$path" >/dev/null' && echo "$JF" | grep -q 'the trigger POST to $path failed'; } \
    || D60="$D60 jenkins_fire does not treat a failed trigger POST as an error (nothing queued, nobody told);"
echo "$JBR" | grep -q '_jenkins_build_appears' \
    || D60="$D60 the retry does not check that the build APPEARS after the trigger (a phantom build waits out the whole timeout);"
nc "$LIBS/common.sh" | grep -q '^AEGIS_NET_SIGS=' \
    || D60="$D60 AEGIS_NET_SIGS missing from common.sh;"
nc "$PHASES/50-jenkins.sh" | grep -q 'jenkins_build_retry ci-images' \
    || D60="$D60 phase 50 does not use jenkins_build_retry for ci-images;"
if [[ -n "$D60" ]]; then fail "builds:$D60"
else pass "FAILURE prints the console; retry ONLY with a network signature (a real failure cuts immediately)"; fi
}
