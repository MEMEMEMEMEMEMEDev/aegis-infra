# title: a tenant build is judged on its own layers — the base's findings are the platform's (inherited, never this build's verdict) — against what runs today
# origin: new in v3 — 2026-09-28 (Rob's H-09) and 2026-09-30 (alpha-arch): an Astro portfolio died at the scan on three OpenSSL CVEs of its base, already judged at the mirror; plan/21 stage 5
check() {
# The base's CVEs stopped an app that could do nothing about them. The
# sidecar reads the scan stage and RUNS --diff-ids and the split by layer.
D262=""
[[ -f "$AEGIS_ROOT/verify/checks/262.py" ]] || { fail "check 262 has no sidecar"; return; }
OUT262="$(python3 "$AEGIS_ROOT/verify/checks/262.py" "$AEGIS_ROOT" 2>&1)"
RC262=$?
(( RC262 == 0 )) || { fail "the exercise of check 262 itself failed (rc $RC262): ${OUT262:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE262="${hit#SCOPE: }" ;;
        *)       D262="$D262 $hit;" ;;
    esac
done <<< "$OUT262"
printf '    %s\n' "${SCOPE262:-the scope was not reported}"
if [[ -n "$D262" ]]; then
    fail "a tenant build is not judged on its own layers:$D262"
else
    pass "the base's findings are inherited and the image's own are judged against what runs, with the platform's policy or not at all (${SCOPE262})"
fi
}
