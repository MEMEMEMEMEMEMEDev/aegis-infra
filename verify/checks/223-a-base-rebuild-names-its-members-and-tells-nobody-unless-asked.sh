# title: a base rebuild names its members, runs the candidate as a pod before signing it, and tells nobody unless asked
# origin: new in v3 — 2026-09-13, one PHP member iterated ten times rebuilt nginx and node ten times and rewrote eleven consumer repos each time: 168 builds, 1 042 agent-minutes
check() {
# A PIPELINE CANNOT KNOW WHO FIRED IT, so nothing in base-images may
# depend on the caller's identity: it depends on what the caller SAYS.
# Two things were implicit and both multiplied a mistake by the whole
# fleet:
#   · MEMBERS empty meant «all of them». A human iterating on one base
#     got three, and the two that nobody touched were rebuilt, re-tagged
#     and propagated for nothing.
#   · propagate had no door. Every member built rewrote the FROM of
#     every consumer and queued two builds per repo, ten times in six
#     hours.
# Now MEMBERS empty is an error, PROPAGATE is a boolean born false, the
# job-dsl and the Jenkinsfile declare the same two parameters (a manual
# «Build with Parameters» shows what the DSL says), and the three
# callers that mean it — image-watch, phase 80, `aegis ci build
# --propagate` — say so in the query. Nothing here reads a description
# and believes it: the descriptions are checked too, because the old
# one still said «empty = every member» after the code stopped doing it.
D223=""
[[ -f "$P/base-images/Jenkinsfile" ]] || { skip "the seed ships no base-images pipeline"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/223.py" ]] || { fail "check 223 has no sidecar"; return; }

OUT223="$(python3 "$AEGIS_ROOT/verify/checks/223.py" "$AEGIS_ROOT" 2>&1)"
RC223=$?
if (( RC223 != 0 )); then
    fail "the exercise of check 223 itself failed (rc $RC223): $OUT223"
    return
fi
SCOPE223=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE223="${hit#SCOPE: }" ;;
        *)       D223="$D223 $hit;" ;;
    esac
done <<< "$OUT223"

printf '    %s\n' "${SCOPE223:-the scope was not reported}"
if [[ -n "$D223" ]]; then
    fail "a base rebuild can still touch what nobody asked for:$D223"
else
    pass "the pipeline and the job-dsl declare the same MEMBERS and PROPAGATE, empty MEMBERS is refused, the candidate runs as a pod under a tenant's restrictions between the push and the signature, PROPAGATE is born false, and the three callers say both ($SCOPE223)"
fi
}
