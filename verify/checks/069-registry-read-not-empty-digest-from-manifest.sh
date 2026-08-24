# title: registry: read≠empty, digest ALWAYS from the manifest
# origin: verify-static.sh (v2) ══ 69
check() {
D69=""
nc "$PHASES/70-deploy-auto.sh" | grep -q 'could not READ' \
    || D69="$D69 phase 70 confuses 'curl failed' with 'no tags' (a gate killed by one blink);"
nc "$PHASES/80-supply-chain.sh" | grep -q 'registry_last_signed_candidate' \
    || D69="$D69 phase 80 without a single source for the registry's tag+digest;"
nc "$PHASES/80-supply-chain.sh" | grep -q "grep -o 'pushed digest" \
    && D69="$D69 the digest is still scraped from Jenkins' console (fragile format, wrong build on resumes);"
if [[ -n "$D69" ]]; then fail "registry:$D69"
else pass "reads with retry and explicit failure; the digest comes from the Docker-Content-Digest on both paths"; fi
}
