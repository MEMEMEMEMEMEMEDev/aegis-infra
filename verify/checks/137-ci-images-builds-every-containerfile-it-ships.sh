# title: ci-images builds every Containerfile it ships, and nothing it does not
# origin: new in v3 — 2026-08-27, when the seed turned out to build two of its four tooling images
check() {
# ci-images/ carries one subdirectory per tooling image (cosign, crane,
# node, tofu) and ONE Jenkinsfile that calls `build_push <subdir> …`
# for each. Nothing ties the two together except this check: a
# Containerfile added without its build_push line is a directory that
# looks like an image and never becomes one, and the consumer that
# names `aegis-ci-<name>` in its pod fails with ImagePullBackOff on a
# tag nobody ever pushed. The seed shipped exactly that until
# 2026-08-27 — two of four built, and the two missing were the ones
# the tofu and node pipelines stand on.
#
# And the other direction: a build_push naming a subdirectory that is
# not there is a build that dies at `test -n "$tag"` on every run.
#
# Only CODE counts. The Jenkinsfile's own comments (`//` in Groovy, `#`
# inside the sh block) mention build_push to explain it, and its
# definition line `build_push() {` is not a call.
JF="$P/ci-images/Jenkinsfile"
[[ -f "$JF" ]] || { fail "$JF does not exist: nothing builds the tooling images"; return; }
[[ -d "$P/ci-images" ]] || { fail "$P/ci-images does not exist"; return; }
D137=""
declare -A called=() shipped=()
while IFS= read -r sub; do
    called["$sub"]=1
done < <(grep -vE '^[[:space:]]*(#|//)' "$JF" | grep -oE '^[[:space:]]*build_push[[:space:]]+[A-Za-z0-9._-]+' | awk '{print $2}')
for cf in "$P"/ci-images/*/Containerfile; do
    [[ -f "$cf" ]] || continue
    sub="$(basename "$(dirname "$cf")")"
    shipped["$sub"]=1
    [[ -n "${called[$sub]:-}" ]] || D137="$D137 ci-images/$sub/Containerfile ships and the Jenkinsfile never calls build_push $sub (an image that never gets pushed);"
done
for sub in "${!called[@]}"; do
    [[ -n "${shipped[$sub]:-}" ]] || D137="$D137 the Jenkinsfile calls build_push $sub and ci-images/$sub/Containerfile does not exist (the build dies on every run);"
done
[[ ${#shipped[@]} -gt 0 ]] || D137="$D137 ci-images/ ships no Containerfile at all — nothing measured;"
if [[ -n "$D137" ]]; then fail "ci-images:$D137"
else pass "${#shipped[@]} tooling images, each with its build_push and no build_push without its image"; fi
}
