# title: every public route has a read-only sibling (GET, HEAD) that does not go through the response-holding buffering
# origin: new in v3 — 2026-09-25, conf: the hub's subtitles stream never reached a browser through traefik; widened 2026-09-27, drop: a 3 GB download was copied to the system SSD in full and took the edge down
check() {
# traefik's `buffering` (the org's `-cuerpo`, a request-body cap) also
# holds the response until it ends: a stream never ends, and a large file
# is copied to disk in full before its first byte goes out. Each public
# route gets a sibling for GET and HEAD — the methods with no body to
# cap — without that middleware and with the rest.
D251=""
[[ -f "$AEGIS_ROOT/verify/checks/251.py" ]] || { fail "check 251 has no sidecar"; return; }
OUT251="$(python3 "$AEGIS_ROOT/verify/checks/251.py" "$AEGIS_ROOT" 2>&1)"
RC251=$?
(( RC251 == 0 )) || { fail "the scan of check 251 itself failed (rc $RC251): ${OUT251:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE251="${hit#SCOPE: }" ;;
        *)       D251="$D251 $hit;" ;;
    esac
done <<< "$OUT251"
printf '    %s\n' "${SCOPE251:-the scope was not reported}"
if [[ -n "$D251" ]]; then
    fail "reads are held by the buffering:$D251"
else
    pass "every public route has a GET/HEAD sibling without the buffering, with headers and rate limit (${SCOPE251})"
fi
}
