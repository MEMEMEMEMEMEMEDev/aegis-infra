# title: the ArgoCD admin password comes from the store, is set without closing sessions in vain, and phase 35 proves it with a real login (#86)
# origin: new in v3 — 2026-10-09, the home instance still logged into ArgoCD with the installer's password, outside the store and out of `aegis rotate check`'s reach
check() {
D278=""
[[ -f "$AEGIS_ROOT/verify/checks/278.py" ]] || { fail "check 278 has no sidecar"; return; }
OUT278="$(python3 "$AEGIS_ROOT/verify/checks/278.py" "$AEGIS_ROOT" 2>&1)"
RC278=$?
(( RC278 == 0 )) || { fail "the exercise of check 278 itself failed (rc $RC278): ${OUT278:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE278="${hit#SCOPE: }" ;;
        *)       D278="$D278 $hit;" ;;
    esac
done <<< "$OUT278"
printf '    %s\n' "${SCOPE278:-the scope was not reported}"
if [[ -n "$D278" ]]; then
    fail "the ArgoCD admin password is not the store's, or nobody proves it:$D278"
else
    pass "phase 30 sets the ArgoCD admin from the store (stdin, a patch file, only when it changed) and drops the installer's Secret; phase 35 logs in through the edge and sees a made-up password rejected; rotation goes through phase 30 (${SCOPE278})"
fi
}
