# title: every Deployment aegis ships for a tenant that serves a port waits in preStop before stopping, with a grace period longer than the wait
# origin: new in v3 — 2026-09-24, plan/19 B-8: every canary rollout dropped ~296 requests in 3 s, on the cloud instance and on Debian
check() {
# On SIGTERM a pod leaves the Service's endpoints and stops at the same
# instant; traefik keeps sending it traffic until the endpoints change
# reaches it. Without a preStop wait, every release of every tenant
# drops the requests in flight. The canary and every template that
# serves a port have to wait first (the native sleep action: the
# runtime images carry no shell for an exec hook).
D245=""
[[ -f "$AEGIS_ROOT/verify/checks/245.py" ]] || { fail "check 245 has no sidecar"; return; }
OUT245="$(python3 "$AEGIS_ROOT/verify/checks/245.py" "$AEGIS_ROOT" 2>&1)"
RC245=$?
(( RC245 == 0 )) || { fail "the scan of check 245 itself failed (rc $RC245): ${OUT245:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE245="${hit#SCOPE: }" ;;
        *)       D245="$D245 $hit;" ;;
    esac
done <<< "$OUT245"
printf '    %s\n' "${SCOPE245:-the scope was not reported}"
if [[ -n "$D245" ]]; then
    fail "a release can drop the people on the site:$D245"
else
    pass "every serving Deployment of the canary and the templates waits in preStop before stopping (${SCOPE245})"
fi
}
