# title: no Application ignores the image it deploys (finding #36)
# origin: new in v3 — 2026-08-27, the canary stayed on an unsigned image while ArgoCD said Synced
check() {
# ignoreDifferences on .spec.template.spec.containers[].image was the
# v2 answer to Kyverno's mutateDigest: with a TAG in git the live image
# carried an appended digest and desired != live forever. In v3 git
# carries the DIGEST (the pipeline's write-digest.mjs, services.yaml for
# the platform's own images), the mutation is a no-op, and ignoring the
# image hides the only change that matters — a new digest. The tenants'
# generator dropped it on 2026-08-03 and wrote why (#36); the canary's
# hand-written App kept it, and on the first clean instance the signed
# build's digest reached git, ArgoCD compared, found no difference,
# skipped the auto-sync, and the canary stayed on the unsigned image
# Kyverno then refused to restart. This check sweeps EVERY Application
# in the seed and the generator's templates for that ignore.
D144=""
HITS="$(cd "$AEGIS_ROOT" && command grep -rn --include='*.yaml' --include='*.py' -E 'containers\[\]?\.image|containers/[0-9]+/image' \
    seed/platform/k8s lib/aegis 2>/dev/null \
    | grep -vE '^\S+:\s*#' | grep -viE '^\S+:.*(#|""").*(#36|no-op|do not|dropped|taken out)' || true)"
# a mention inside prose that explains the finding is fine; a path
# expression under ignoreDifferences is not — tell them apart by the
# YAML/py shape: the expression sits alone on its line (a list item or
# a quoted string), the prose does not
BAD="$(echo "$HITS" | grep -E ':\s*(- |")?\.?spec\.template\.spec\.containers\[\]\.image"?\s*$|jsonPointers.*containers/[0-9]+/image' || true)"
[[ -n "$BAD" ]] && D144="$D144 an Application ignores the image it deploys: $(echo "$BAD" | cut -d: -f1,2 | tr '\n' ' ')(with the digest in git the Kyverno mutation is a no-op, and this ignore switches auto-sync off — #36);"
N="$(cd "$AEGIS_ROOT" && command grep -rl --include='*.yaml' -E '^kind: Application$' seed/platform/k8s 2>/dev/null | wc -l)"
printf '    %s Application files swept in seed/platform/k8s (plus the generator)\n' "$N"
if [[ -n "$D144" ]]; then fail "image ignored:$D144"
else pass "no Application ignores the image it deploys: git carries the digest, so every new digest is a difference ArgoCD acts on"; fi
}
