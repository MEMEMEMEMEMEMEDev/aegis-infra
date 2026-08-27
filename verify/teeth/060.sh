# teeth for check 060 — generated on 2026-08-23 and VERIFIED:
# each red was applied to a copy of the tree and the check turned red.

# removes from the artifact exactly what the check says it measures
red_1() {
    grep -vE 'jenkins_build_retry ci-images' "$AEGIS_ROOT/init/phases/50-jenkins.sh" > "$AEGIS_ROOT/init/phases/50-jenkins.sh.tooth" \
        && mv "$AEGIS_ROOT/init/phases/50-jenkins.sh.tooth" "$AEGIS_ROOT/init/phases/50-jenkins.sh"
}

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$AEGIS_ROOT/init/phases/50-jenkins.sh"; }

# 2026-08-27: back to POST /build for every job — the parameterized one refuses it in silence
red_2() {
    python3 - "$AEGIS_ROOT/lib/jenkins.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '        jenkins_fire "$job" "$query" || return 1\n'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, '        jenkins_post "/job/$job/build" >/dev/null\n', 1))
PY
}
# the phantom-build check disappears: a trigger that did not take waits out the timeout
red_3() {
    python3 - "$AEGIS_ROOT/lib/jenkins.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '        _jenkins_build_appears "$job" "$next" 120 || return 1\n'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "", 1))
PY
}
