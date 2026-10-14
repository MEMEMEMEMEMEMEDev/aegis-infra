# title: phase 80 says why the canary keeps its public bases: a base the mirror cannot serve is a warning, not a mute death under set -e
# origin: new in v3 — 2026-10-13, the Ubuntu lab VM: golang and alpine held at the door, and phase 80 ended «FAILED» without one word on why
check() {
D282=""
[[ -f "$AEGIS_ROOT/verify/checks/282.py" ]] || { fail "check 282 has no sidecar"; return; }
OUT282="$(python3 "$AEGIS_ROOT/verify/checks/282.py" "$AEGIS_ROOT" 2>&1)"
RC282=$?
(( RC282 == 0 )) || { fail "the exercise of check 282 itself failed (rc $RC282): ${OUT282:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE282="${hit#SCOPE: }" ;;
        *)       D282="$D282 $hit;" ;;
    esac
done <<< "$OUT282"
printf '    %s\n' "${SCOPE282:-the scope was not reported}"
if [[ -n "$D282" ]]; then
    fail "phase 80 dies or goes mute when the mirror cannot serve the canary's bases:$D282"
else
    pass "phase 80 repoints the canary's bases when the mirror serves them and says so when it cannot, without dying under set -e (${SCOPE282})"
fi
}
