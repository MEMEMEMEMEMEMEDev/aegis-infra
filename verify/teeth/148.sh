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
