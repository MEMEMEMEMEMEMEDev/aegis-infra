# title: the CI's pod templates pin the same version everywhere, and the one their owner builds
# origin: new in v3 — 2026-09-18, six Jenkinsfiles name the same image by hand (plan/17)
check() {
# A PIN COPIED SIX TIMES IS SIX PINS.
#
# The agent, kaniko, trivy, crane and cosign are written by hand in
# every Jenkinsfile of the platform — the agent in seven of them. There
# is no include, no shared library, nothing that makes them agree. So a
# bump is six simultaneous edits, and a bump that does five is invisible
# until a pipeline that nobody ran that week builds on a version
# somebody meant to leave behind.
#
# And when the image is one this instance BUILDS, there is a second way
# to disagree: the pod template says `aegis-ci-cosign:v2.6.3` and the
# pin that decides what that image contains says something else. The CI
# would then ask for a tag the chain does not produce.
D210=""
[[ -f "$LIBS/aegis/pins.py" ]] || { skip "there is no pin reader: the templates cannot be compared"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/210.py" ]] || { fail "check 210 has no sidecar"; return; }

OUT210="$(python3 "$AEGIS_ROOT/verify/checks/210.py" "$AEGIS_ROOT" 2>&1)"
RC210=$?
if (( RC210 != 0 )); then
    fail "the exercise of check 210 itself failed (rc $RC210): $OUT210"
    return
fi
SCOPE210=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE210="${hit#SCOPE: }" ;;
        *)       D210="$D210 $hit;" ;;
    esac
done <<< "$OUT210"

printf '    %s\n' "${SCOPE210:-the scope was not reported}"
if [[ -n "$D210" ]]; then
    fail "the CI's pod templates disagree:$D210"
else
    pass "every image of the pod templates carries one version across every file, and what this instance builds is pinned at what it builds ($SCOPE210)"
fi
}
