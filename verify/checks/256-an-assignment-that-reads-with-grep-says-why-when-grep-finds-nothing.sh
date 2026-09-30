# title: under errexit, an assignment that reads with grep has a way out for «grep found nothing», so the next line can say why
# origin: new in v3 — 2026-09-28, Rob's instance (his H-05): `aegis image request --allow` ended rc 1 with no word, ten times, when the image asked for was the only one that failed
check() {
# `NAME="$( … grep … )"` carries grep's exit status to set -e: when grep
# finds nothing — no other culprit, no hash yet, no tunnel_name — the
# script ends right there, before the line that would have said so.
# The sidecar follows each $( … ) to its closing parenthesis in code
# only (check 253's reader) and asks for `|| true` inside or a `||`
# after it.
D256=""
[[ -f "$AEGIS_ROOT/verify/checks/256.py" ]] || { fail "check 256 has no sidecar"; return; }
OUT256="$(python3 "$AEGIS_ROOT/verify/checks/256.py" "$AEGIS_ROOT" 2>&1)"
RC256=$?
(( RC256 == 0 )) || { fail "the scan of check 256 itself failed (rc $RC256): ${OUT256:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE256="${hit#SCOPE: }" ;;
        *)       D256="$D256 $hit;" ;;
    esac
done <<< "$OUT256"
printf '    %s\n' "${SCOPE256:-the scope was not reported}"
if [[ -n "$D256" ]]; then
    fail "an assignment reads with grep and has no way out when grep finds nothing — set -e ends the script before the next line can say why (add || true inside, or || die \"…\" after):$D256"
else
    pass "every assignment that reads with grep under errexit has a way out for «found nothing» (${SCOPE256})"
fi
}
