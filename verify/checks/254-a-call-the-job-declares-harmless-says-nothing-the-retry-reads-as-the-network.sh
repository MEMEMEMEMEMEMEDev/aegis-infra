# title: a call a pipeline declares harmless keeps its stderr out of the console, and its notice says nothing the retry reads as the network
# origin: new in v3 — 2026-09-23, cloud instance, finding 13: `Could not resolve host: vlogs-events` from a best-effort event made phase 80 retry a real failure
check() {
# `|| echo 'NOTICE: … does NOT fail for this'` is the pipeline saying the
# call does not matter. Its curl error in the console said the opposite to
# jenkins_build_retry, which greps the console for AEGIS_NET_SIGS.
D254=""
[[ -f "$AEGIS_ROOT/verify/checks/254.py" ]] || { fail "check 254 has no sidecar"; return; }
OUT254="$(python3 "$AEGIS_ROOT/verify/checks/254.py" "$AEGIS_ROOT" 2>&1)"
RC254=$?
(( RC254 == 0 )) || { fail "the scan of check 254 itself failed (rc $RC254): ${OUT254:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE254="${hit#SCOPE: }" ;;
        *)       D254="$D254 $hit;" ;;
    esac
done <<< "$OUT254"
printf '    %s\n' "${SCOPE254:-the scope was not reported}"
if [[ -n "$D254" ]]; then
    fail "a harmless call can make a real failure look like the network:$D254"
else
    pass "every call a pipeline declares harmless discards its stderr and its notice matches no network signature (${SCOPE254})"
fi
}
