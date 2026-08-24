# title: every git push of the phases goes verified
# origin: verify-static.sh (v2) ══ 30, part a — split in v3
check() {
# A failed push that carries on = a local commit that was never pushed
# → kustomize broken ONE phase later (run #9). The probe-pushes
# (bash -c) go with retry_net and their exit propagates through the &&
# chain.
BAD_PUSH="$(grep -rn 'git -C .* push' "$PHASES/" | nc_hits | grep -v 'git_push_verified' | grep -v 'retry_net' || true)"
if [[ -n "$BAD_PUSH" ]]; then fail "git push WITHOUT verification:"$'\n'"$BAD_PUSH"
else pass "every git push verified (git_push_verified / retry_net)"; fi
}
