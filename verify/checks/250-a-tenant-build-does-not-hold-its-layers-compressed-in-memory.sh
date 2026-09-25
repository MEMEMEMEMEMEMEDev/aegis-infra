# title: a tenant's kaniko build does not hold its layers compressed in memory (a CUDA wheel layer is several GB)
# origin: new in v3 — 2026-09-25, conf-motor build #3: kaniko OOMKilled at its 2Gi limit, the build ended ABORTED
check() {
# kaniko's compressed caching keeps every layer compressed in memory while
# it snapshots. A `pip install` of CUDA wheels is a layer of several GB;
# at the template's 2Gi ceiling the container was OOMKilled and Jenkins
# reported ABORTED, nothing more. The flag has to be on the executor call
# the build stage RUNS, not in a comment.
T="$P/docs/protocols/templates/Jenkinsfile.app"
[[ -f "$T" ]] || { skip "the artifact has no app Jenkinsfile template"; return; }
# The executor call, comments dropped: from `/kaniko/executor` to the
# first line that does not continue with a backslash.
CALL="$(nc "$T" | awk '/\/kaniko\/executor/{on=1} on{print} on && !/\\$/{exit}')"
if [[ -z "$CALL" ]]; then
    fail "the app template runs no /kaniko/executor: this check has lost its subject"
elif ! grep -qE -- '--compressed-caching=false([[:space:]]|\\|$)' <<< "$CALL"; then
    fail "kaniko builds tenant images with compressed caching on: a layer of CUDA wheels is held compressed in memory and the 2Gi container is OOMKilled (the build reads ABORTED)"
else
    pass "the tenant build's kaniko runs with --compressed-caching=false: large layers stay on disk, under the CI quota's memory ceiling"
fi
}
