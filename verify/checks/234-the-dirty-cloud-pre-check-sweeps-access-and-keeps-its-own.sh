# title: the dirty-cloud pre-check of phase 25 sweeps the Access leftovers of a previous instance and keeps its own
# origin: new in v3 — 2026-09-23, second cloud VM: tunnel and CNAMEs swept, five 409 application_already_exists in the apply
check() {
# Reinstalling against the same zone is the cutover. The pre-check swept
# the previous instance's tunnel and CNAMEs by name and left its Access
# applications, policies and service token in the account; the apply
# then died on 409 for every application. The sweep has to see the
# other half, delete it in the order Cloudflare accepts, spare what this
# instance's state owns, and be gated on both edges.
D234=""
[[ -f "$AEGIS_ROOT/verify/checks/234.py" ]] || { fail "check 234 has no sidecar"; return; }
OUT234="$(python3 "$AEGIS_ROOT/verify/checks/234.py" "$AEGIS_ROOT" 2>&1)"
RC234=$?
(( RC234 == 0 )) || { fail "the scan of check 234 itself failed (rc $RC234): ${OUT234:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE234="${hit#SCOPE: }" ;;
        *)       D234="$D234 $hit;" ;;
    esac
done <<< "$OUT234"
printf '    %s\n' "${SCOPE234:-the scope was not reported}"
if [[ -n "$D234" ]]; then
    fail "a previous instance's Access resources can still break the apply:$D234"
else
    pass "phase 25 lists the account's Access apps, policies and service token, deletes what is not in this instance's state before the apply, apps first, and gates it on both edges (${SCOPE234})"
fi
}
