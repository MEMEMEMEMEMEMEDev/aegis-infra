# title: every template is complete and no template FROM comes off the internet
# origin: new in v3 — 2026-08-29, the day `base` was the only template and its two FROMs were docker.io
check() {
# seed/templates/<name>/ is the ONLY thing a new organization is handed:
# `aegis app new <org> --template <name>` writes it, the template
# evaporates (journeys/design.md §0.3) and from then on it is somebody's
# repo forever. Whatever is wrong in here is wrong in every app born
# from it, and nothing goes back to fix it.
#
# TWO PROPERTIES, and each one has a failure that is silent for a while:
#
# 1. THE FIVE PIECES. A template is a contract plus a repo skeleton, and
#    the skeleton is not complete until it can be built and deployed:
#      · contract.yaml.tpl  — without it `new --template` stops, but
#        only after resolving values, and the error blames the command;
#      · repos/<svc>/Containerfile — without it there is nothing to
#        build and the pipeline fails on a repo the operator just made;
#      · repos/<svc>/k8s/base/ + k8s/overlays/dev/ — the overlay is
#        where the pipeline WRITES the digest, so a skeleton with the ci
#        script and no overlay fails at the deploy stage with «I could
#        not find these images», which reads like a bug in the script;
#      · repos/<svc>/ci/ — the script that writes that digest;
#      · README.md — the one place that says what may be changed and
#        what may not. A template whose contract nobody explains gets
#        edited exactly where it must not be.
#
# 2. NO `FROM` OFF THE INTERNET. Until 2026-08-29 the `base` template
#    shipped `FROM docker.io/library/golang:1.26-alpine` and
#    `FROM docker.io/library/alpine:3.21`: an unmirrored, unscanned,
#    unsigned image, pinned by a MUTABLE TAG, entering the pipeline that
#    afterwards signs the result with the aegis key. It is the hole
#    mirror-images was built to close (its own header tells how the
#    canary was the last place it hid) — and the template was reopening
#    it for every organization that would ever be created.
#    So a template's FROM is one of two things: a placeholder resolved
#    at instantiation against the LIVE registry (which is the only party
#    that knows the internal digest — the mirror rewrites the manifest
#    as it copies, so images.txt's digest pulls nothing here), or an
#    already-pinned `@sha256:` reference. Never a bare tag.
#
# And the USER, which is one line and the difference between a pod that
# runs and a pod that is rejected at admission: tenant namespaces are
# PSS restricted, so the last USER of the final stage has to be NUMERIC
# and not 0. `USER nginx` fails runAsNonRoot because the kubelet cannot
# read the image's /etc/passwd to prove the name is not root. Same
# clause check 138 asserts on the bases the platform owns, for the same
# reason, one level up.
T="$SEED/templates"
[[ -d "$T" ]] || { fail "$T does not exist: the template catalogue is gone and there is nothing to instantiate from"; return; }
D148=""
n_tpl=0 ; n_cf=0
for tpl in "$T"/*/; do
    [[ -d "$tpl" ]] || continue
    name="$(basename "$tpl")"
    n_tpl=$((n_tpl+1))
    [[ -f "$tpl/contract.yaml.tpl" ]] || D148="$D148 $name: no contract.yaml.tpl;"
    [[ -f "$tpl/README.md" ]] || D148="$D148 $name: no README.md (nothing says what may be changed and what may not);"
    if [[ ! -d "$tpl/repos" ]] || [[ -z "$(ls -A "$tpl/repos" 2>/dev/null)" ]]; then
        D148="$D148 $name: repos/ empty — a contract with no skeleton is half a template;"
        continue
    fi
    for svc in "$tpl"/repos/*/; do
        [[ -d "$svc" ]] || continue
        s="$name/$(basename "$svc")"
        cf="$svc/Containerfile"
        [[ -f "$cf" ]] || { D148="$D148 $s: no Containerfile;"; }
        [[ -d "$svc/k8s/base" ]] || D148="$D148 $s: no k8s/base/;"
        [[ -f "$svc/k8s/base/kustomization.yaml" ]] || D148="$D148 $s: k8s/base/ without a kustomization.yaml;"
        [[ -f "$svc/k8s/overlays/dev/kustomization.yaml" ]] \
            || D148="$D148 $s: no k8s/overlays/dev/kustomization.yaml — the pipeline has nowhere to write the digest;"
        [[ -n "$(ls -A "$svc/ci" 2>/dev/null)" ]] || D148="$D148 $s: ci/ empty (nothing writes the digest into the overlay);"
        [[ -f "$cf" ]] || continue
        n_cf=$((n_cf+1))
        # Comments are stripped FIRST: several of these Containerfiles
        # tell the story of the docker.io line they replaced, and a
        # check that bit its own documentation would teach people to
        # stop writing it (the class already paid for in checks 22, 66,
        # 71 and 104).
        code="$(joincont "$cf" | grep -vE '^[[:space:]]*#')"
        while IFS= read -r from; do
            [[ -z "$from" ]] && continue
            # legitimate: a __FROM_*__ placeholder, or an @sha256: pin.
            grep -qE '(__FROM_[A-Z0-9_]+__|@sha256:[0-9a-f]{64})' <<< "$from" && continue
            D148="$D148 $s: «$(echo "$from" | tr -s ' ')» is neither a __FROM_*__ placeholder nor pinned by @sha256: — an image by tag is a mutable pointer entering the pipeline that signs the result;"
        done <<< "$(grep -E '^[[:space:]]*FROM[[:space:]]' <<< "$code" || true)"
        last_user="$(grep -E '^[[:space:]]*USER[[:space:]]' <<< "$code" | tail -1 | awk '{print $2}')"
        if [[ -z "$last_user" ]]; then
            D148="$D148 $s: no USER: the image runs as root and PSS restricted rejects it at admission;"
        elif ! [[ "$last_user" =~ ^[1-9][0-9]*(:[0-9]+)?$ ]]; then
            D148="$D148 $s: the last USER is '$last_user', and it has to be numeric and not 0: runAsNonRoot cannot be proven for a name (the kubelet does not read the image's /etc/passwd);"
        fi
    done
done
# A sweep that swept nothing is not a verdict: zero templates means
# `--template` has no catalogue, and this check stopped measuring.
(( n_tpl > 0 )) || D148="$D148 seed/templates/ has no template: the catalogue --template offers is empty;"
printf '    %s template(s) · %s Containerfile(s)\n' "$n_tpl" "$n_cf"
if [[ -n "$D148" ]]; then fail "templates:$D148"
else pass "$n_tpl template(s) complete (contract, skeleton, k8s/base + overlay, ci and README) and no FROM off the internet: placeholder or digest, numeric non-root USER"; fi
}
