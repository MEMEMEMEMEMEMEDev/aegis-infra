#!/usr/bin/env bash
# aegis-init lib/jenkins.sh — access to the Jenkins API from INSIDE
# the pod (server.insecure behind the edge: always http://localhost).
# Rule A27 in full: the password touches neither LOCAL nor REMOTE
# argv — it travels through the exec's stdin into a temporary netrc
# (600) in the pod that is deleted on the way out. CSRF crumb for the
# POSTs (crumb + session cookie: the crumb is only good with the
# session that issued it).
# Consumers: every phase that builds — the list is not kept here
# because it drifted (85 and 87 arrived and nobody updated it); what
# matters is the precondition, and it is stated in the code below.

set -euo pipefail

# ── how a job is ADDRESSED ──────────────────────────────────────────
# Jenkins nests items by repeating /job/: the main branch of the
# multibranch ai-gateway-mb is /job/ai-gateway-mb/job/main, never
# /job/ai-gateway-mb/main. Run of 2026-09-01: phase 87 wrote the second
# form, Jenkins answered 404, and the caller reported «the job does not
# exist» about a job that was there with its branch indexed. The
# comment above that line even said the branch is the buildable item,
# so what failed was not the idea, it was writing the path by hand.
#
# Hence this: the caller names the item (`ai-gateway-mb/main`, or
# `ai-gateway-mb/job/main`, or plain `ci-images`) and the LIBRARY
# builds the URL. Idempotent — a `job` segment already there is
# dropped and rebuilt — so the call sites that were already correct
# keep working untouched. A Jenkins item literally named `job` would be
# invisible to this, and is a name nothing in the artifact creates.
_jenkins_job() {   # <item path> -> the nested path Jenkins addresses
    local IFS=/ seg out=""
    for seg in $1; do
        [[ -n "$seg" && "$seg" != "job" ]] || continue
        out="${out:+$out/job/}$seg"
    done
    printf '%s' "$out"
}

# _jenkins_pass_file: the jenkins-admin password into a tmpfs file.
# Prefers the one generated in THIS run (phase 50); if it is not there
# (a later --from run), it reads it from the cluster — mechanics
# without showing it.
_jenkins_pass_file() {
    # Run of 2026-09-01: with no tmpfs this expanded to "/jenkins_admin_pass"
    # under set -u… which is an UNBOUND VARIABLE error whose only visible
    # consequence was a 401 three lines later, read as «the job does not
    # exist». The precondition is stated where it is needed, the same way
    # ansible_become_setup states it in lib/common.sh:
    : "${SECRETS_TMP:?lib/jenkins.sh requires secrets_workdir first — a phase that talks to Jenkins opens the tmpfs BEFORE its first build}"
    local f="$SECRETS_TMP/jenkins_admin_pass"
    if [[ ! -s "$f" ]]; then
        # umask 077 (P2 audit 2026-07-18): the redirection created the
        # file 644 and the chmod arrived AFTERWARDS — a window for
        # reading. The subshell scopes the umask to this write:
        ( umask 077
          kubectl -n jenkins-system get secret jenkins-admin \
              -o jsonpath='{.data.password}' | base64 -d > "$f" )
        chmod 600 "$f"
    fi
    printf '%s' "$f"
}

# _jenkins_netrc_stdin: emits the netrc on stdout (to be piped into
# the exec). machine=localhost because curl runs INSIDE the pod.
_jenkins_netrc_stdin() {
    local pf; pf="$(_jenkins_pass_file)"
    printf 'machine localhost login admin password '
    cat "$pf"
    printf '\n'
}

# jenkins_get <path> — authenticated GET; prints the body.
#   e.g.: jenkins_get /job/ci-images/lastBuild/api/json
# P1.7 audit 2026-07-18: the in-pod curls had no --max-time and the
# kubectl exec had no timeout — a hung socket (the operator's network,
# a pod half dying) hung the phase INDEFINITELY, worse than a timeout
# because it leaves no diagnosis. 60s of curl (consoleText can be big)
# + 90s of hard cap on the exec:
jenkins_get() {
    local path="$1"
    _jenkins_netrc_stdin | \
    timeout 90 kubectl -n jenkins-system exec -i sts/jenkins -c jenkins -- \
        bash -c 'umask 077; N="$(mktemp)"; cat > "$N"
                 curl -fsS --max-time 60 --netrc-file "$N" "http://localhost:8080$1"
                 rc=$?
                 rm -f "$N"
                 exit $rc' _ "$path"
}

# jenkins_get_code <path> — ONLY the http_code (no -f: a 404 is not an
# error here — jenkins_wait_build needs it to tell "the build does not
# exist yet" from "the API is broken" — P1.6):
jenkins_get_code() {
    local path="$1"
    _jenkins_netrc_stdin | \
    timeout 90 kubectl -n jenkins-system exec -i sts/jenkins -c jenkins -- \
        bash -c 'umask 077; N="$(mktemp)"; cat > "$N"
                 curl -sS --max-time 60 -o /dev/null -w "%{http_code}" \
                      --netrc-file "$N" "http://localhost:8080$1"
                 rc=$?
                 rm -f "$N"
                 exit $rc' _ "$path"
}

# jenkins_post <path> — authenticated POST with a CSRF crumb.
#   e.g.: jenkins_post /job/ci-images/build
jenkins_post() {
    local path="$1"
    _jenkins_netrc_stdin | \
    timeout 90 kubectl -n jenkins-system exec -i sts/jenkins -c jenkins -- \
        bash -c 'umask 077; N="$(mktemp)"; J="$(mktemp)"; cat > "$N"
                 CRUMB="$(curl -fsS --max-time 30 --netrc-file "$N" -c "$J" \
                   "http://localhost:8080/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)")"
                 curl -fsS --max-time 60 --netrc-file "$N" -b "$J" -H "$CRUMB" \
                   -X POST "http://localhost:8080$1"
                 rc=$?
                 rm -f "$N" "$J"
                 exit $rc' _ "$path"
}

# jenkins_next_build <job> — the number the NEXT build will have.
# Capture it BEFORE triggering (POST /build, or a push that fires the
# webhook) and wait for THAT build. Run #9: after the trigger, Jenkins
# takes ~5-10s to promote the new build to lastBuild; in that window
# lastBuild = the PREVIOUS one — an old FAILURE cut the gate short in
# 1s while the new build was running towards SUCCESS. Same class as
# the App self bug C: reading the state of the WRONG operation.
# P1.6 audit 2026-07-18: with no retry and no validation, a transient
# returned "" or "null" and the caller waited for a PHANTOM build until
# the timeout (1800s). retry_net + shape-check ^[0-9]+$ — invalid after
# the retries = explicit failure HERE (errexit makes it fatal in the
# caller's assignment):
_jenkins_next_raw() {   # prints the number ONLY if it validates (a
    local out             # failed attempt must not contaminate the
                          # caller's $()):
    out="$(jenkins_get "/job/$(_jenkins_job "$1")/api/json" 2>/dev/null \
           | jq -r '.nextBuildNumber // empty')" || return 1
    [[ "$out" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "$out"
}
jenkins_next_build() {
    local job="$1" n=""
    if ! n="$(retry_net 3 _jenkins_next_raw "$job")"; then
        log_error "jenkins_next_build $job: no valid nextBuildNumber after 3 attempts — the Jenkins API is down or the job does not exist"
        return 1
    fi
    printf '%s' "$n"
}

# _jenkins_quota_stall <window_s> — bug from run #11: with the
# ResourceQuota exhausted the kubernetes plugin CANNOT create the
# build's pod → the build stays queued FOREVER and the wait waited in
# SILENCE until the timeout (the operator diagnosed it by hand against
# the controller's logs: "exceeded quota: jenkins-quota"). The evidence
# lives there — it is detected and REPORTED with the RQ's real usage
# and the live pods (orphans/overlaps consume quota). Only numbers and
# pod names: zero sensitive material. Returns 0 if it detected the
# stall (so the caller can count it), 1 if not.
_jenkins_quota_stall() {
    local window="${1:-60}"
    kubectl -n jenkins-system logs sts/jenkins -c jenkins \
        --since="${window}s" 2>/dev/null | grep -m1 'exceeded quota' >&2 \
        || return 1
    log_warn "Jenkins CANNOT create the build's pod: ResourceQuota exhausted (the line above = the controller's evidence)"
    kubectl -n jenkins-system get resourcequota jenkins-quota >&2 || true
    log_warn "live pods in the ns (orphans/overlaps consume quota; cleaning them frees it):"
    kubectl -n jenkins-system get pods --no-headers >&2 || true
    return 0
}

# jenkins_wait_build <job> <timeout_s> <build_n> — waits for SUCCESS
# of the SPECIFIC build build_n (mandatory: captured with
# jenkins_next_build BEFORE the trigger). A GET 404 = the build has not
# started yet (asynchronous webhook/quiet period) = RUNNING, not an
# error. Fails fast if it ended FAILURE/ABORTED (a real failure ≠
# has-not-started-yet). And if the build "does not start" because the
# RQ rejects the pod, it SAYS so on every lap (run #11) instead of
# waiting mutely.
jenkins_wait_build() {
    local job="$1" timeout="${2:-1200}" build="${3:?jenkins_wait_build requires build_n (jenkins_next_build BEFORE the trigger — lastBuild race #9)}"
    local waited=0 every=20 result api_errs=0
    while :; do
        # P1.6 audit 2026-07-18: EVERY error of the GET was mapped to
        # "RUNNING" — a 401 (creds), a downed pod or a hung exec waited
        # out the WHOLE timeout in silence. Only the 404 is a
        # legitimate "has not started yet"; any other sustained error
        # (6 laps ≈ 2 min) cuts short with the code in plain sight:
        if result="$(jenkins_get "/job/$(_jenkins_job "$job")/$build/api/json" 2>/dev/null \
                     | jq -r '.result // "RUNNING"')" && [[ -n "$result" ]]; then
            api_errs=0
        else
            local code
            code="$(jenkins_get_code "/job/$(_jenkins_job "$job")/$build/api/json" 2>/dev/null || echo 000)"
            if [[ "$code" == "404" ]]; then
                api_errs=0
                result=RUNNING   # the webhook/quiet period has not created it yet
            else
                api_errs=$(( api_errs + 1 ))
                log_warn "the Jenkins API is not answering for build $job#$build (http=$code, $api_errs/6)"
                if (( api_errs >= 6 )); then
                    log_error "the Jenkins API has gone ~2 min without answering (last http=$code) — this is NOT a slow build, it is Jenkins/creds/exec broken"
                    kubectl -n jenkins-system get pods >&2 || true
                    return 1
                fi
                result=RUNNING
            fi
        fi
        case "$result" in
            SUCCESS) log_ok "build $job#$build: SUCCESS"; return 0 ;;
            FAILURE|ABORTED|UNSTABLE)
                # F-C run #15 (H7 applied to builds): two FAILUREs in a
                # row without ONE line of the console — the cause lives
                # there and the operator dug it out by hand:
                log_error "build $job#$build ended $result — tail of the console:"
                jenkins_get "/job/$(_jenkins_job "$job")/$build/consoleText" 2>/dev/null \
                    | tail -n 30 >&2 || true
                return 1 ;;
        esac
        (( waited >= timeout )) && {
            log_error "build $job#$build: timeout ${timeout}s (state: $result)"
            jenkins_get "/job/$(_jenkins_job "$job")/$build/consoleText" 2>/dev/null \
                | tail -n 15 >&2 || true
            _jenkins_quota_stall "$timeout" || true
            return 1; }
        _jenkins_quota_stall "$every" || true
        sleep "$every"; waited=$(( waited + every ))
    done
}

# jenkins_build_retry <job> [timeout_s] [tries] [query] — triggers the
# build through the API (jenkins_fire: the endpoint the job accepts,
# the query when it carries parameters) and waits; F-D run #15: with the operator's mobile
# network the build can die from a transient (the "server misbehaving"
# of the upstream DNS took down the ArgoCD sync IN THE SAME MINUTE as
# build #1). If the FAILURE carries a NETWORK signature in the console
# (AEGIS_NET_SIGS, common.sh) it is RE-FIRED — each manual retry cost a
# whole run of the phase. A FAILURE with no network signature = a REAL
# failure → cut short NOW (the console was already printed by
# jenkins_wait_build). Captures next BEFORE the POST (race #9):
# jenkins_job_parameterized <job> — 0 if the job declares parameters.
# Jenkins has TWO trigger endpoints and each refuses the other's job:
# /build on a parameterized job expects a form and throws ("Error while
# serving .../build" in the controller's log, nothing in the caller's);
# /buildWithParameters on a plain job throws "not parameterized". The
# job knows which one it is; ask it.
jenkins_job_parameterized() {
    jenkins_get "/job/$(_jenkins_job "$1")/api/json?tree=property%5BparameterDefinitions%5Bname%5D%5D" 2>/dev/null       | jq -e '[.property[]? | select(.parameterDefinitions? and (.parameterDefinitions | length > 0))] | length > 0'       >/dev/null
}

# jenkins_fire <job> [query] — the trigger POST, on the endpoint the job
# accepts, with the query (url-encoded k=v&k=v) when it carries
# parameters. First clean instance, 2026-08-27: phase 80.7 fired
# base-images (it has MEMBERS) through /build, Jenkins refused it in
# its own log only, and the wait sat 45 minutes on a build that never
# existed. A failed POST is an error HERE, said out loud.
jenkins_fire() {
    local job="$1" query="${2:-}" path
    if jenkins_job_parameterized "$job"; then
        path="/job/$(_jenkins_job "$job")/buildWithParameters${query:+?$query}"
    else
        [[ -z "$query" ]] || { log_error "jenkins_fire $job: parameters given ('$query') to a job that declares none"; return 1; }
        path="/job/$(_jenkins_job "$job")/build"
    fi
    jenkins_post "$path" >/dev/null         || { log_error "jenkins_fire $job: the trigger POST to $path failed — nothing was queued (Jenkins' own log has the reason: kubectl -n jenkins-system logs jenkins-0 -c jenkins | grep 'Error while serving')"; return 1; }
}

# _jenkins_build_appears <job> <n> [secs] — after the trigger, build <n>
# must come into existence (or the job must at least be queued) within
# <secs>; otherwise the trigger did not take, and waiting the build's
# whole timeout for it is the silence of 2026-08-27. Returns 0 when it
# appeared, 1 when it did not.
_jenkins_build_appears() {
    local job="$1" n="$2" secs="${3:-120}" waited=0 code
    while (( waited < secs )); do
        code="$(jenkins_get_code "/job/$(_jenkins_job "$job")/$n/api/json" 2>/dev/null || echo 000)"
        [[ "$code" == "200" ]] && return 0
        jenkins_get "/job/$(_jenkins_job "$job")/api/json?tree=inQueue" 2>/dev/null | jq -e '.inQueue == true' >/dev/null && return 0
        sleep 10; waited=$(( waited + 10 ))
    done
    log_error "build $job#$n never appeared in ${secs}s and the job is not queued — the trigger did not take (a build that does not exist is not a slow build)"
    return 1
}

jenkins_build_retry() {
    local job="$1" timeout="${2:-1800}" tries="${3:-3}" query="${4:-}" i next
    for ((i = 1; i <= tries; i++)); do
        next="$(jenkins_next_build "$job")"
        jenkins_fire "$job" "$query" || return 1
        _jenkins_build_appears "$job" "$next" 120 || return 1
        if jenkins_wait_build "$job" "$timeout" "$next"; then
            return 0
        fi
        if jenkins_get "/job/$(_jenkins_job "$job")/$next/consoleText" 2>/dev/null \
             | grep -qiE "$AEGIS_NET_SIGS"; then
            log_warn "build $job#$next: FAILURE with a transient NETWORK signature (attempt $i/$tries) — re-firing"
            continue
        fi
        log_error "build $job#$next: FAILURE with NO network signature — a real failure, it is not retried (console above)"
        return 1
    done
    log_error "build $job: $tries attempts with network failures — the network cannot carry the build; retry once it settles"
    return 1
}
