# title: a static front compiles in the pipeline (ci/compile.sh in aegis-ci-node), and the image build only copies dist/ onto the signed runtime
# origin: new in v3 — 2026-09-28, a user's instance (their H-08): Astro inside kaniko failed 4 builds of 4; 2026-09-30, the Arch lab VM: the template's build image was retained at the door (npm CVEs past their window)
check() {
# Compiling inside kaniko failed every Astro build, and needed a build
# image the door retained. The sidecar reads the template and the tenant
# pipeline, and RUNS the template's ci/compile.sh on a copy.
D260=""
[[ -f "$AEGIS_ROOT/verify/checks/260.py" ]] || { fail "check 260 has no sidecar"; return; }
OUT260="$(python3 "$AEGIS_ROOT/verify/checks/260.py" "$AEGIS_ROOT" 2>&1)"
RC260=$?
(( RC260 == 0 )) || { fail "the exercise of check 260 itself failed (rc $RC260): ${OUT260:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE260="${hit#SCOPE: }" ;;
        *)       D260="$D260 $hit;" ;;
    esac
done <<< "$OUT260"
printf '    %s\n' "${SCOPE260:-the scope was not reported}"
if [[ -n "$D260" ]]; then
    fail "a static front does not compile in the pipeline, or the image build still compiles:$D260"
else
    pass "the static front compiles in the pipeline's compile stage and the image build only copies dist/ onto the runtime (${SCOPE260})"
fi
}
