# title: a base run builds a member after the members it stands on, and on what the run just built for them
# origin: new in v3 — 2026-09-23, cloud instance, base-images #3: php died MANIFEST_UNKNOWN on the house's nginx digest shipped in the seed; a clean install needed two passes
check() {
# php stands on aegis-base-nginx. The seed ships that FROM pinned to a
# digest born in the house's registry; in a clean one it does not exist.
# The run walked MEMBERS as asked and built php on the shipped pin, and
# only the propagation of the new nginx fixed it — for the next run.
# siblings.sh orders the run and pins each member's FROM to what the run
# built; the sidecar RUNS it on a copy of the seed.
D252=""
[[ -f "$AEGIS_ROOT/verify/checks/252.py" ]] || { fail "check 252 has no sidecar"; return; }
OUT252="$(python3 "$AEGIS_ROOT/verify/checks/252.py" "$AEGIS_ROOT" 2>&1)"
RC252=$?
(( RC252 == 0 )) || { fail "the exercise of check 252 itself failed (rc $RC252): ${OUT252:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE252="${hit#SCOPE: }" ;;
        *)       D252="$D252 $hit;" ;;
    esac
done <<< "$OUT252"
printf '    %s\n' "${SCOPE252:-the scope was not reported}"
if [[ -n "$D252" ]]; then
    fail "a base run can build a member on a sibling it has not built:$D252"
else
    pass "a member is built after the siblings it stands on and pinned to what this run built; a failed or unbuilt sibling stops it by name (${SCOPE252})"
fi
}
