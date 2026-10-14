# title: --help after a verb is help, and writes nothing
# origin: new in v3 — 2026-10-02, the Debian lab VM: `aegis state backup --help` wrote a real bundle to a file named «--help»
check() {
D275=""
[[ -f "$AEGIS_ROOT/verify/checks/275.py" ]] || { fail "check 275 has no sidecar"; return; }
OUT275="$(python3 "$AEGIS_ROOT/verify/checks/275.py" "$AEGIS_ROOT" 2>&1)"
RC275=$?
(( RC275 == 0 )) || { fail "the exercise of check 275 itself failed (rc $RC275): ${OUT275:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE275="${hit#SCOPE: }" ;;
        *)       D275="$D275 $hit;" ;;
    esac
done <<< "$OUT275"
printf '    %s\n' "${SCOPE275:-the scope was not reported}"
if [[ -n "$D275" ]]; then
    fail "a verb takes --help for an argument:$D275"
else
    pass "every verb of the commands that exec a verb script answers --help with its usage and writes nothing, and state backup refuses a flag as its output (${SCOPE275})"
fi
}
