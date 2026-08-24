# teeth for check 084 (every write destination survives a clone)
#
# The automatic generator had picked «delete .git/index» as the
# mutation: the check did turn red, yes, but for having broken git on
# the tree, not for the defect it watches. A tooth that bites for the
# wrong reason is worse than no tooth at all, because it gives
# confidence.
#
# The real defect: a phase writes into a directory of platform/ that
# the seed does not ship, so on a new machine —where platform/ is born
# from a clone of the seed— that write fails.
red_1() {
    printf '\ncp x "$PLATFORM_DIR/k8s/base/folder-the-seed-does-not-ship/file.yaml"\n' \
        >> "$AEGIS_ROOT/init/phases/85-observability.sh"
}
