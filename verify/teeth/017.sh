# teeth of check 017 (the files the phases reference exist)
# Bug class 4: the phase runs for half an hour and dies at the last
# step because a file was not there. It is caught EARLIER, by reading
# the code.
#
# The first red of this tooth discovered that half the check had been
# left dead when $AEGIS_V2_ROOT was renamed: it looked for a variable
# that no longer exists, so it had no subjects and passed green. The
# two reds below cover the two halves.
red_1() {
    printf '\nansible-playbook ansible/playbooks/does-not-exist.yml\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"
}
red_2() {
    printf '\nsource "$AEGIS_ROOT/lib/does-not-exist.sh"\n' >> "$AEGIS_ROOT/init/phases/35-gitops.sh"
}
