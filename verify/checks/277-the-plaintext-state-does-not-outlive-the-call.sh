# title: the edge's plaintext state does not outlive a wrapper call, and destroy/backup/restore/rotate read the encrypted copy
# origin: new in v3 — 2026-10-09, the home instance: terraform.tfstate and its .backup sat in the env for two weeks with the tunnel token and the Access secret in the clear, and one grep printed both
check() {
D277=""
[[ -f "$AEGIS_ROOT/verify/checks/277.py" ]] || { fail "check 277 has no sidecar"; return; }
OUT277="$(python3 "$AEGIS_ROOT/verify/checks/277.py" "$AEGIS_ROOT" 2>&1)"
RC277=$?
(( RC277 == 0 )) || { fail "the exercise of check 277 itself failed (rc $RC277): ${OUT277:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE277="${hit#SCOPE: }" ;;
        *)       D277="$D277 $hit;" ;;
    esac
done <<< "$OUT277"
printf '    %s\n' "${SCOPE277:-the scope was not reported}"
if [[ -n "$D277" ]]; then
    fail "the edge's state is left in the clear, or a caller still looks for the plaintext:$D277"
else
    pass "the wrapper shreds the plaintext state and its backups once the encrypted copy is proven, keeps it (and says so) when it cannot prove it, and destroy, backup, restore and rotate read the encrypted copy (${SCOPE277})"
fi
}
