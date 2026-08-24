# teeth for check 086 (the seed carries no baked-in instance)
# It has already leaked twice. An instance inside the artifact means
# the next installation is born pointing at somebody else's machine.
#
# The red goes through the sub-check that is ALWAYS active (the literal
# repo owner). The one that contrasts against the machine's conf only
# runs if there is an instance — and discovering that in v3 it no
# longer found it was this tooth's doing.
red_1() {
    printf '\n# the repo: git@github.com:ejemplo-org/ops-stack-v2.git\n' \
        >> "$AEGIS_ROOT/seed/platform/edge.yaml"
}
# control: the CORRECT way of naming the same thing in the artifact
control_1() {
    printf '\n# the repo: git@github.com:__GH_OWNER__/__PLATFORM_REPO__.git\n' \
        >> "$AEGIS_ROOT/seed/platform/edge.yaml"
}
