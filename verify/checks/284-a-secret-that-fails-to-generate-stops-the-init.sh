# title: a secret that fails to generate stops the init, and empty material never reaches the store
# origin: new in v3 — 2026-10-13 review (A-4): bash drops errexit inside $( ), so a failing openssl in gen_hex32 returned the path of a 0-byte file that persist_secret encrypted, roundtripped and kept
check() {
D284=""
[[ -f "$AEGIS_ROOT/verify/checks/284.py" ]] || { fail "check 284 has no sidecar"; return; }
OUT284="$(python3 "$AEGIS_ROOT/verify/checks/284.py" "$AEGIS_ROOT" 2>&1)"
RC284=$?
(( RC284 == 0 )) || { fail "the exercise of check 284 itself failed (rc $RC284): ${OUT284:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE284="${hit#SCOPE: }" ;;
        *)       D284="$D284 $hit;" ;;
    esac
done <<< "$OUT284"
printf '    %s\n' "${SCOPE284:-the scope was not reported}"
if [[ -n "$D284" ]]; then
    fail "a generator can fail in silence, or empty material can be persisted:$D284"
else
    pass "errexit reaches command substitutions in every lib that sets it, each generator refuses to return less than it must, and the store refuses empty material (${SCOPE284})"
fi
}
