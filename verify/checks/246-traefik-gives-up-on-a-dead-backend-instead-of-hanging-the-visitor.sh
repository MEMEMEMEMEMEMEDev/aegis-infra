# title: traefik gives up on a dead backend (dial 5 s, headers within 60 s) instead of hanging the visitor
# origin: new in v3 — 2026-09-24, plan/19 B-9: during a 90 s network cut every visitor hung, traefik waited with no limit
check() {
# With no forwarding timeouts traefik dials for 30 s and waits for
# response headers forever. A backend that is dead or cut off does not
# produce an error, it produces a visitor staring at a spinner. The
# timeouts are static arguments, so they live in traefik's values.
D246=""
[[ -f "$AEGIS_ROOT/verify/checks/246.py" ]] || { fail "check 246 has no sidecar"; return; }
OUT246="$(python3 "$AEGIS_ROOT/verify/checks/246.py" "$AEGIS_ROOT" 2>&1)"
RC246=$?
(( RC246 == 0 )) || { fail "the scan of check 246 itself failed (rc $RC246): ${OUT246:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE246="${hit#SCOPE: }" ;;
        *)       D246="$D246 $hit;" ;;
    esac
done <<< "$OUT246"
printf '    %s\n' "${SCOPE246:-the scope was not reported}"
if [[ -n "$D246" ]]; then
    fail "a dead backend can still hang the visitor:$D246"
else
    pass "traefik bounds the wait for a backend: a short dial and a header timeout under Cloudflare's own cut (${SCOPE246})"
fi
}
