# teeth of check 007 (the resources of the kustomizations exist)
# kustomize is ATOMIC: a nonexistent resource breaks the whole build
# and NO object of that App is applied, not even the ones that were
# fine.
#
# CORRECTED on 2026-08-24. The previous red_1 appended to
# `k8s/base/platform/jenkins/kustomization.yaml`, a file that does NOT
# exist (that directory holds only values.yaml). The `>>` invented it
# with a single bare list item, YAML parsed that as a LIST, and the
# check's `doc.get(...)` raised AttributeError — a traceback, rc 1, and
# the runner scored it as "it bites".
#
# It was a tooth that bit by ACCIDENT. The path it claims to prove —
# "a referenced resource is missing" — was never exercised once. That
# is worse than no tooth at all: a missing tooth is visible to check
# 199, and a lying one is not.
#
# Now it mutates a kustomization that really exists.
red_1() {
    printf '  - file-that-does-not-exist.yaml\n' >> \
        "$AEGIS_ROOT/seed/platform/k8s/base/registry-system/kustomization.yaml"
}

# The same thing on the `generators:` list, which the check sweeps too
# and which no tooth touched: a ksops generator entry pointing at a
# .enc.yaml that is not there produces exactly the same atomic failure.
red_2() {
    printf 'generators:\n  - generator-that-is-not-there.yaml\n' >> \
        "$AEGIS_ROOT/seed/platform/k8s/base/kyverno-policies/kustomization.yaml"
}

# And the shape the check used to DIE on instead of reporting: a
# kustomization.yaml that is not a mapping at all. It has to come out
# red as a broken artifact, not as a traceback.
red_3() {
    printf -- '- this is a list, not a Kustomization\n' > \
        "$AEGIS_ROOT/seed/platform/k8s/base/kyverno/kustomization.yaml"
}

# control: listing a resource that DOES exist is the most ordinary edit
# there is on a kustomization, and it cannot come out red.
#
# (The first version of this control appended to a kustomization that
#  does not exist, with a `>>` that invented it — repeating, inside the
#  control, the very defect the reds above were fixed for. It turned
#  red, correctly. Written down because it is the second time today the
#  same mistake was made in the same file.)
control_1() {
    sed -i 's|^  - registry\.yaml$|  - registry.yaml\n  - netpol.yaml|' \
        "$AEGIS_ROOT/seed/platform/k8s/base/registry-system/kustomization.yaml"
    printf 'apiVersion: networking.k8s.io/v1\nkind: NetworkPolicy\nmetadata:\n  name: legit\n  namespace: registry-system\nspec:\n  podSelector: {}\n' \
        > "$AEGIS_ROOT/seed/platform/k8s/base/registry-system/netpol.yaml"
}
