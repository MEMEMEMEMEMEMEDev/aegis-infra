# title: every rate limiter counts per visitor (not per connection) behind the tunnel, and traefik runs two replicas with room to queue
# origin: new in v3 — 2026-09-24, plan/19 B-1 and B-3: one bucket for the whole internet, and traefik OOMKilled at ~1600 req/s
check() {
# Behind the Cloudflare tunnel every connection traefik receives comes
# from cloudflared. A rateLimit with no sourceCriterion counts by that
# connection, so «50 per visitor» was 50 for everybody at once. The
# criterion scans X-Forwarded-For from the right and skips the pod range
# the entrypoints already trust. And the door itself needs room: one
# replica with 256Mi died under load and took every site with it.
D244=""
[[ -f "$AEGIS_ROOT/verify/checks/244.py" ]] || { fail "check 244 has no sidecar"; return; }
OUT244="$(python3 "$AEGIS_ROOT/verify/checks/244.py" "$AEGIS_ROOT" 2>&1)"
RC244=$?
(( RC244 == 0 )) || { fail "the scan of check 244 itself failed (rc $RC244): ${OUT244:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE244="${hit#SCOPE: }" ;;
        *)       D244="$D244 $hit;" ;;
    esac
done <<< "$OUT244"
printf '    %s\n' "${SCOPE244:-the scope was not reported}"
if [[ -n "$D244" ]]; then
    fail "a limiter or the door itself is not ready for public traffic:$D244"
else
    pass "every rate limiter counts per visitor through the range traefik trusts, and traefik runs two replicas with room to queue (${SCOPE244})"
fi
}
