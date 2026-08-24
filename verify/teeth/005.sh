# teeth of check 005 (the git paths of the Applications exist)
# An App pointing at a directory that is not in the repo stays
# «Unknown» forever, and the reason shows up in no alert.
red_1() {
    sed -i '0,/^    path: /s|^    path: .*|    path: k8s/base/directory-that-does-not-exist|' \
        "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/ci-supply-tenants.yaml"
}
control_1() { printf '\n# legitimate comment\n' >> "$AEGIS_ROOT/seed/platform/k8s/argocd-apps/ci-supply-tenants.yaml"; }
