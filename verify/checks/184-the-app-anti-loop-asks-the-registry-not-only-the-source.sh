# title: the application pipeline's anti-loop asks the registry, not only whether the source changed
# origin: new in v3 — 2026-09-03, measured putting the portfolio back up on a fresh installation
check() {
# MEASURED 2026-09-03, installing from zero.
#
# `detect-change` skips the build when the last commit touched only
# `k8s/`, and that is right: the deploy stage commits the digest there,
# and without the cut the pipeline would build itself forever.
#
# But the reasoning holds for the installation that BUILT that image
# and for no other. An application repo travels between installations,
# and every installation is born with an empty registry. On the fresh
# one the last commit was `deploy: main-000005 por digest`, this stage
# said «only manifests», and the job went green in SIXTY SECONDS having
# built nothing. The Deployment was then denied at admission:
#
#     failed to verify image .../portafolio@sha256:788dfb…:
#     no signatures found
#
# a message about a signature, for an image that was never there.
#
# Nothing was red anywhere near the cause. The build succeeded, the
# pipeline succeeded, ArgoCD reported OutOfSync, and the sentence the
# operator had to read was about cryptography. It is the same hole
# phase 87 had for the AI images (check 174) and it takes the same
# fix, one floor down: the question is not «did the source change?»
# but «is it in THIS registry, signed?».
#
# cosign answers both halves at once, which is why it is the right
# instrument here: an absent image and an unsigned one both fail.
#
# And the bootstrap window has to survive: before the supply chain
# exists there is no signing key, and a stage that failed closed there
# could never build an installation's first image. That is a fact this
# check requires, not an exception it tolerates.
D184=""
TPL="$AEGIS_ROOT/seed/platform/docs/protocols/templates/Jenkinsfile.app"
[[ -f "$TPL" ]] || { skip "the seed ships no Jenkinsfile.app: this check has no subject"; return; }

OUT="$(python3 "$AEGIS_ROOT/verify/checks/184.py" "$AEGIS_ROOT" 2>/dev/null)"
RC=$?
if (( RC != 0 )); then
    fail "the scan of check 184 itself failed (rc $RC) and this check measured nothing about the anti-loop"
    return
fi
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    D184="$D184 $hit;"
done <<< "$OUT"

N="$(python3 "$AEGIS_ROOT/verify/checks/184.py" "$AEGIS_ROOT" 2>&1 >/dev/null | awk '/__COUNT__/{print $2}')"
printf '    %s facts asked of the skip, over the stage with its prose stripped\n' "${N:-0}"
if [[ -n "$D184" ]]; then fail "a build can be skipped for an image this installation does not have:$D184"
else pass "the anti-loop verifies against this registry, with this installation's key, the digests the deploy stage pinned, before deciding to skip, and stands aside while there is no key yet"; fi
}
