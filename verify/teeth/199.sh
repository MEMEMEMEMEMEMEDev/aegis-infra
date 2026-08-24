# teeth for meta-check 199 (every check has an executable tooth)
#
# 199 does not measure the ARTIFACT: it measures the verifier. Its
# subject is the files of verify/, so taking a command away from the
# product —what the generated tooth used to do— does not touch it. Its
# three failure modes:
red_1() {
    # a new check without a tooth
    printf '# title: check without a tooth\ncheck() { pass "nothing"; }\n' \
        > "$AEGIS_ROOT/verify/checks/997-no-tooth.sh"
}
red_2() {
    # the debt list naming a check that does not exist (an allowlist
    # that ages is an allowlist that covers up new holes)
    printf '998\n' > "$AEGIS_ROOT/verify/teeth/PENDIENTES"
}
red_3() {
    # and the list naming one that DOES have a tooth: if that were not
    # red, somebody could put a check in there and disable it without
    # anything warning
    printf '001\n' > "$AEGIS_ROOT/verify/teeth/PENDIENTES"
}
# control: a new check WITH its tooth bothers nobody
control_1() {
    printf '# title: check with a tooth\ncheck() { pass "nothing"; }\n' \
        > "$AEGIS_ROOT/verify/checks/996-with-tooth.sh"
    printf 'red_1() { :; }\n' > "$AEGIS_ROOT/verify/teeth/996.sh"
}
