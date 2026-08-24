# teeth of check 003 (every placeholder has a declared owner)
#
# The defect this check prevents: a __WHATEVER__ that nobody fills in
# travels to the cluster as-is and shows up as a literal hostname
# "__ROOT_DOMAIN__" in production.

# an orphan placeholder in a manifest of the artifact
red_1() {
    printf '\n# __PLACEHOLDER_WITH_NO_OWNER__\n' >> "$AEGIS_ROOT/seed/platform/edge.yaml"
}

# and in a .tf, which is the other extension the check sweeps
red_2() {
    printf '\n# __ANOTHER_ORPHAN__\n' >> "$AEGIS_ROOT/seed/platform/tofu/modules/cloudflare-access/main.tf"
}

# control: a placeholder that DOES have an owner cannot turn it red —
# if it does, the check is not reading the allowlist but shouting at
# any __X__, which is what would make it useless.
control_1() {
    printf '\n# __ROOT_DOMAIN__\n' >> "$AEGIS_ROOT/seed/platform/edge.yaml"
}

# an orphan in seed/templates/, which until 2026-08-24 this check did
# not sweep: each of the operator's app repos is born from there.
red_3() {
    printf '\n// __ORPHAN_IN_TEMPLATE__\n' >> "$AEGIS_ROOT/seed/templates/base/repos/app/main.go"
}

# an orphan in a .md of the artifact: blindness by extension.
red_4() {
    printf '\n<!-- __ORPHAN_WITHOUT_EXTENSION__ -->\n' \
        >> "$AEGIS_ROOT/seed/platform/docs/protocols/organization.md"
}

# control: a template-class placeholder (owner: aegis app) cannot turn
# it red — if it does, the check did not derive the class.
control_2() {
    printf '\n// __ORG__\n' >> "$AEGIS_ROOT/seed/templates/base/repos/app/main.go"
}
