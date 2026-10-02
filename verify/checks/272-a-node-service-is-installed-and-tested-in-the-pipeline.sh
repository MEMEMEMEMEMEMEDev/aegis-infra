# title: a node service is installed and tested in the pipeline, and the image build only copies it
# origin: new in v3 — 2026-10-02, plan/21 stage 9: service-node still built on node:22.23.1-alpine inside kaniko, the image the door retained on alpha-arch and that had to be mirrored before the template could even be instantiated
check() {
D272=""
[[ -f "$AEGIS_ROOT/verify/checks/272.py" ]] || { fail "check 272 has no sidecar"; return; }
OUT272="$(python3 "$AEGIS_ROOT/verify/checks/272.py" "$AEGIS_ROOT" 2>&1)"
RC272=$?
(( RC272 == 0 )) || { fail "the exercise of check 272 itself failed (rc $RC272): ${OUT272:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE272="${hit#SCOPE: }" ;;
        *)       D272="$D272 $hit;" ;;
    esac
done <<< "$OUT272"
printf '    %s\n' "${SCOPE272:-the scope was not reported}"
if [[ -n "$D272" ]]; then
    fail "service-node still builds inside the image:$D272"
else
    pass "service-node's ci/compile.sh installs, tests and prunes in the agent (a red test stops it), and its Containerfile is one FROM that only copies (${SCOPE272})"
fi
}
