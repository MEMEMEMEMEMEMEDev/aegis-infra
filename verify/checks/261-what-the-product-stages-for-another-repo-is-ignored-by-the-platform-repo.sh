# title: the staging area the product fills for another repo (.aegis-app/) is ignored by the platform repo, as the code has always said
# origin: new in v3 — 2026-09-26 (hackathon, noted) and 2026-09-30 (the Arch lab VM, measured): the untracked staging area blocked every `aegis seed apply` after an `aegis app new`
check() {
# org.py said .aegis-app/ was in the .gitignore; it was not. The sidecar
# reads STAGING_DIR from the code and asks git check-ignore.
D261=""
[[ -f "$AEGIS_ROOT/verify/checks/261.py" ]] || { fail "check 261 has no sidecar"; return; }
OUT261="$(python3 "$AEGIS_ROOT/verify/checks/261.py" "$AEGIS_ROOT" 2>&1)"
RC261=$?
(( RC261 == 0 )) || { fail "the exercise of check 261 itself failed (rc $RC261): ${OUT261:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE261="${hit#SCOPE: }" ;;
        *)       D261="$D261 $hit;" ;;
    esac
done <<< "$OUT261"
printf '    %s\n' "${SCOPE261:-the scope was not reported}"
if [[ -n "$D261" ]]; then
    fail "the staging area is not ignored by the platform repo:$D261"
else
    pass "the staging area the product fills for the apps' repos is ignored by the platform repo (${SCOPE261})"
fi
}
