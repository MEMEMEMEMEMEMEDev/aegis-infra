# teeth of check 029 (builds awaited by NUMBER, not lastBuild)
# The race of run #9: lastBuild may be ANOTHER build triggered in
# between, and the phase takes for good something it did not build.
red_1() { printf '\ncurl -s "$JENKINS/job/x/lastBuild/api/json"\n' >> "$AEGIS_ROOT/init/phases/50-jenkins.sh"; }
