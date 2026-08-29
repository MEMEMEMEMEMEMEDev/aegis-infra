# teeth of check 148 (every template is complete and no FROM comes off
# the internet)
#
# The defect this check prevents: seed/templates/ is the ONLY thing a
# new organization is handed, the template evaporates the second it is
# instantiated, and nothing ever goes back to fix what it wrote wrong.
# The two reds below are the two real regressions: the docker.io FROM
# the `base` template carried until 2026-08-29, and a piece of the
# skeleton going missing.

# THE REGRESSION ITSELF: the FROM the template shipped until
# 2026-08-29 — an unmirrored image, by a mutable tag, entering the
# pipeline that afterwards signs the result with the aegis key.
red_1() {
    sed -i 's|^FROM __FROM_GOLANG__ AS build|FROM docker.io/library/golang:1.26-alpine AS build|' \
        "$AEGIS_ROOT/seed/templates/base/repos/app/Containerfile"
}

# the same hole in the runtime stage of another template: whoever adds
# a template copies a neighbour, and one line is all it takes.
red_2() {
    sed -i 's|^FROM __FROM_NODE__$|FROM docker.io/nginxinc/nginx-unprivileged:1.27-alpine|' \
        "$AEGIS_ROOT/seed/templates/static/repos/app/Containerfile"
}

# a template with no README: nothing says what may be changed and what
# may not, and it gets edited exactly where it must not be.
red_3() {
    rm -f "$AEGIS_ROOT/seed/templates/static/README.md"
}

# the overlay disappears: the pipeline has nowhere to write the digest
# and dies at the deploy stage with «I could not find these images»,
# which reads like a bug in the script and is not.
red_4() {
    rm -f "$AEGIS_ROOT/seed/templates/service-node/repos/app/k8s/overlays/dev/kustomization.yaml"
}

# the last USER stops being numeric: the pod is rejected at admission
# because the kubelet cannot read the image's /etc/passwd to prove the
# name is not root.
red_5() {
    sed -i 's|^USER 65532:65532$|USER nonroot|' \
        "$AEGIS_ROOT/seed/templates/static/repos/app/Containerfile"
}

# control: an extra, harmless file in a skeleton cannot turn it red —
# a template is free to ship whatever else it needs.
control_1() {
    printf '# what the build has no business seeing\nnode_modules\n' \
        > "$AEGIS_ROOT/seed/templates/service-node/repos/app/.dockerignore"
}

# control: a COMMENT telling the story of the docker.io line that was
# removed cannot turn it red. If it does, the check bites its own
# documentation and teaches people to stop writing it — the class
# already paid for in checks 22, 66, 71 and 104.
control_2() {
    printf '\n# it used to say FROM docker.io/library/alpine:3.21, and that was the hole\n' \
        >> "$AEGIS_ROOT/seed/templates/base/repos/app/Containerfile"
}

# THE HOLE THE `tail -1` LEFT: a USER in the BUILD stage and none in the
# final one. The image that RUNS is root, PSS restricted rejects it at
# admission — and the old check read the last USER of the FILE, so it
# said PASS. A USER does not survive a FROM.
red_6() {
    f="$AEGIS_ROOT/seed/templates/base/repos/app/Containerfile"
    sed -i 's|^USER 65532:65532$||' "$f"
    sed -i 's|^WORKDIR /src$|WORKDIR /src\nUSER 65532:65532|' "$f"
}

# a placeholder nobody owns: _FROM_IMAGES does not know it, so
# `app new --template` dies after having resolved every other value,
# and the template can never be instantiated. Property 2 still sees a
# well-formed __FROM_*__ and is happy.
red_7() {
    sed -i 's|^FROM __FROM_ALPINE__$|FROM __FROM_DEBIAN__|' \
        "$AEGIS_ROOT/seed/templates/base/repos/app/Containerfile"
}

# an image the mirror list does not declare is legal — that is how the
# java template ships — but ONLY while the README says so. Take the
# name out of the README and the template becomes one that stops
# halfway through an afternoon with no warning anywhere.
red_8() {
    sed -i '/node:22.23.1-alpine/d' "$AEGIS_ROOT/seed/templates/static/README.md"
}

# control: a row in _FROM_IMAGES that no template uses yet cannot turn
# it red. The table is allowed to be ahead of the catalogue; what is
# forbidden is a template ahead of the table.
control_3() {
    sed -i 's|^    "__FROM_PYTHON__": "python:3.12-slim",$|    "__FROM_PYTHON__": "python:3.12-slim",\n    "__FROM_REDIS__": "redis:8.6.4-alpine",|' \
        "$AEGIS_ROOT/libexec/aegis-app"
}
