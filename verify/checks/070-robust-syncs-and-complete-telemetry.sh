# title: robust syncs + complete telemetry (P1.3/P1.11/class G)
# origin: verify-static.sh (v2) ══ 70
check() {
D70=""
ASY70="$(body_of argo_sync "$LIBS/common.sh")"
echo "$ASY70" | grep -q 'IN FLIGHT' \
    || D70="$D70 argo_sync dies if selfHeal has an operation in flight (the patch bounces and it looked like a real failure);"
echo "$ASY70" | grep -q 'net_refires' \
    || D70="$D70 argo_sync re-fires on network errors with NO cap (the broad signature masks a broken service);"
echo "$ASY70" | grep -q '_gate_record' \
    || D70="$D70 the syncs leave no trace in gates.jsonl (2 of the run's 3 real failures went unrecorded);"
ASG70="$(body_of argo_secrets_gate "$LIBS/common.sh")"
echo "$ASG70" | grep -q '_gate_record' \
    || D70="$D70 argo_secrets_gate without a pass/fail record;"
RN70="$(body_of retry_net "$LIBS/common.sh")"
echo "$RN70" | grep -q 'delay \* 3' \
    || D70="$D70 retry_net is still on a fixed 3×5s against outages that last minutes (no backoff);"
JWB70="$(body_of jenkins_wait_build "$LIBS/jenkins.sh")"
echo "$JWB70" | grep -q 'jenkins_get_code' \
    || D70="$D70 jenkins_wait_build maps EVERY API error to RUNNING (401/dead pod waited out the timeout in silence);"
NB70="$(body_of jenkins_next_build "$LIBS/jenkins.sh")"
echo "$NB70" | grep -q 'retry_net' \
    || D70="$D70 jenkins_next_build without retry or validation (a phantom next = 1800s lost);"
nc "$AEGIS_ROOT"/init/phases/*.sh | grep -q 'REG_HOST="registry\.' \
    && D70="$D70 REG_HOST duplicated by hand in the phases (the single source is REGISTRY_HOST_INTERNAL);"
nc "$LIBS/common.sh" | grep -q '^REGISTRY_HOST_INTERNAL=' \
    || D70="$D70 REGISTRY_HOST_INTERNAL missing from common.sh;"
nc "$PHASES/40-registry-pki.sh" | grep -q 'clusterip-coincide-con-el-service' \
    || D70="$D70 REGISTRY_CLUSTER_IP is never validated against the real Service;"
if [[ -n "$D70" ]]; then fail "syncs/telemetry:$D70"
else pass "selfHeal adopted, real backoff, 404≠broken-API, complete gates.jsonl, registry with a validated single source"; fi
}
