# title: jenkins_wait_build DIAGNOSES an exhausted quota (run #11)
# origin: verify-static.sh (v2) ══ 35
check() {
# RQ full → the plugin does not create the pod → the build never
# starts and the wait waited MUTE until the timeout. The body of the
# wait must invoke the detector, and the detector must look at the
# real evidence ('exceeded quota' in the controller logs) —
# non-comment:
JW_BODY="$(body_of jenkins_wait_build "$LIBS/jenkins.sh" \
    | nc)"
JLIB_NC="$(nc "$LIBS/jenkins.sh")"
# the PERIODIC diagnosis inside the loop (the $every window) is
# demanded, not only the one at the timeout — the first tooth revealed
# that "some call in the body" let through a mute wait whose diagnosis
# only came at the end:
if echo "$JW_BODY" | grep -q '_jenkins_quota_stall "\$every"' \
   && echo "$JLIB_NC" | grep -q "grep -m1 'exceeded quota'"; then
    pass "the build wait detects and reports the stall caused by the ResourceQuota"
else
    fail "jenkins_wait_build waits MUTE for a build the quota will never let start (run #11)"
fi
}
