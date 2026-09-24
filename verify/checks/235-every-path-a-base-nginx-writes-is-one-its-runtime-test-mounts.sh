# title: every path a base's nginx writes at run time (pid, temp paths) lies under what its runtime test mounts writable
# origin: new in v3 — 2026-09-24, second cloud VM: aegis-base-nginx died on /tmp/nginx.pid under the smoke test's read-only root
check() {
# A base aegis owns is run once as a pod under a tenant's restrictions
# before it is signed, with an emptyDir on every path its
# runtime-test.yaml names writable. Those same paths are its contract
# with the consumers. The nginx member's conf writes its pid and temp
# files under /tmp and its runtime test did not name /tmp: the first
# clean install that ran the smoke test on it never got past phase 80.
D235=""
[[ -f "$AEGIS_ROOT/verify/checks/235.py" ]] || { fail "check 235 has no sidecar"; return; }
OUT235="$(python3 "$AEGIS_ROOT/verify/checks/235.py" "$AEGIS_ROOT" 2>&1)"
RC235=$?
(( RC235 == 0 )) || { fail "the scan of check 235 itself failed (rc $RC235): ${OUT235:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE235="${hit#SCOPE: }" ;;
        *)       D235="$D235 $hit;" ;;
    esac
done <<< "$OUT235"
printf '    %s\n' "${SCOPE235:-the scope was not reported}"
if [[ -n "$D235" ]]; then
    fail "a base writes where its runtime test does not mount:$D235"
else
    pass "every pid and temp path a base's nginx writes lies under a path its runtime test mounts writable (${SCOPE235})"
fi
}
