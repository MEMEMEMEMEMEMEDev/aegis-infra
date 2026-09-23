# title: cleaning the cloud cleans the encrypted state too, and no plaintext state copy reaches disk or git
# origin: new in v3 — 2026-09-23, the first cloud instance hit a deleted tunnel three runs in a row because the encrypted state kept it
check() {
# Phase 25 deletes the leftovers of a failed apply in Cloudflare and
# purges the local tfstate. Since #46 the state lives ENCRYPTED and the
# wrapper decrypts it before every apply: the purge of the plaintext was
# blind, and the deleted tunnel came back. `tofu state rm` through the
# wrapper is the edit that reaches the encrypted copy — and it leaves
# plaintext backups behind that git did not ignore. Driven in 232.py.
D232=""
[[ -f "$AEGIS_ROOT/verify/checks/232.py" ]] || { fail "check 232 has no sidecar"; return; }
OUT232="$(python3 "$AEGIS_ROOT/verify/checks/232.py" "$AEGIS_ROOT" 2>&1)"
RC232=$?
(( RC232 == 0 )) || { fail "the scan of check 232 itself failed (rc $RC232): ${OUT232:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE232="${hit#SCOPE: }" ;;
        *)       D232="$D232 $hit;" ;;
    esac
done <<< "$OUT232"
printf '    %s\n' "${SCOPE232:-the scope was not reported}"
if [[ -n "$D232" ]]; then
    fail "a deleted tunnel can still come back from the state, or a plaintext state can reach git:$D232"
else
    pass "phase 25 drops the tunnel from the encrypted state through the wrapper, keeps Access, shreds the plaintext copies, and the seed ignores every plaintext state shape while versioning the encrypted one (${SCOPE232})"
fi
}
