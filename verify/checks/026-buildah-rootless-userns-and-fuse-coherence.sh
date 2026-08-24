# title: buildah rootless: userns enabled + fuse coherence (bug D)
# origin: verify-static.sh (v2) ══ 26
check() {
# Run #8: the buildah pod (identical to the v1 one that was GREEN on
# WSL2) died on Ubuntu 24.04 with "failed to make mount private:
# permission denied" — Ubuntu >= 23.10 blocks unprivileged userns by
# default (apparmor). The fix is a PLATFORM one (sysctl in
# bootstrap-host + a gate that exercises it in phase 20), NOT touching
# the proven manifest.
# a) the sysctl is in the bootstrap — anchored to the REAL sysctl task
#    (`name: kernel...`), not to any mention: the stat of the path
#    /proc/sys also contains the string (the tooth revealed it):
D26=""
# $BH was born in check 24 and this one used it «on loan»: one of the
# four couplings that v2's single file hid. Every check computes its
# own (or asks lib.sh for it) — otherwise --only 26 was measuring air.
BH="$P/ansible/playbooks/bootstrap-host.yml"
nc "$BH" | grep -qE 'name:\s*kernel\.apparmor_restrict_unprivileged_userns' \
    || D26="$D26 the userns sysctl is missing from bootstrap-host;"
# b) phase 20 EXERCISES it (a real unshare, not a proxy):
nc "$PHASES/20-k3s.sh" | grep -q 'unshare --user' \
    || D26="$D26 the unprivileged-userns gate is missing from phase 20;"
# c) W-05: buildah REMOVED — kaniko builds WITHOUT privileges (it
#    extracts layers straight to the FS, it does not do the mounts that
#    killed rootless buildah in #8/#9). The Jenkinsfiles must have
#    neither privileged nor /dev/fuse; jenkins-system stops being PSS
#    privileged. The escape to the node from the build (untrusted code
#    via npm ci) is closed.
#    (mention≠use: 'privileged: true'/'path: /dev/fuse' are checked,
#    which do NOT appear in comments, not the string 'buildah'.)
# These two came out of $ROOT/platform — the INSTANCE, not the
# artifact. It is the trap that v2's verifier denounced in its own
# header and that slipped in three times anyway (26, 90, 91): with
# product and instance in the same folder, the wrong path gave the same
# result and nobody saw it. Here they look at the SEED.
for jf in "$P"/ci-images/Jenkinsfile \
          "$P"/docs/protocols/templates/Jenkinsfile.app; do
    b="$(basename "$(dirname "$jf")")/$(basename "$jf")"
    grep -q 'privileged: true' "$jf" && D26="$D26 $b has privileged:true (W-05: the build must not escalate to the node);"
    grep -q 'path: /dev/fuse'   "$jf" && D26="$D26 $b mounts /dev/fuse (hostPath);"
    grep -q 'kaniko'            "$jf" || D26="$D26 $b does not use kaniko (did buildah come back?);"
done
grep -q 'pod-security.kubernetes.io/enforce: privileged' \
     "$P/k8s/base/platform/jenkins-secrets/bundle.yaml" \
    && D26="$D26 jenkins-system is still PSS privileged (the build would escape to the node);"
if [[ -n "$D26" ]]; then fail "build-without-privileges:$D26"
else pass "build WITHOUT privileges (W-05): kaniko in both Jenkinsfiles, no /dev/fuse, jenkins-system PSS baseline; userns sysctl+gate present"; fi
}
