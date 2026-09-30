# title: every aegis command finds the instance's age key from any directory, and an explicit key is respected
# origin: new in v3 — 2026-09-30, alpha-arch: `aegis app new` run from the product checkout died at its secrets step (sops looked for keys.txt; the key is announced only by a direnv .envrc)
check() {
# The key was found only by bash commands that source lib/secrets.sh,
# or in a shell standing where direnv acts. The sidecar RUNS bin/aegis.
D263=""
[[ -f "$AEGIS_ROOT/verify/checks/263.py" ]] || { fail "check 263 has no sidecar"; return; }
OUT263="$(python3 "$AEGIS_ROOT/verify/checks/263.py" "$AEGIS_ROOT" 2>&1)"
RC263=$?
(( RC263 == 0 )) || { fail "the exercise of check 263 itself failed (rc $RC263): ${OUT263:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE263="${hit#SCOPE: }" ;;
        *)       D263="$D263 $hit;" ;;
    esac
done <<< "$OUT263"
printf '    %s\n' "${SCOPE263:-the scope was not reported}"
if [[ -n "$D263" ]]; then
    fail "an aegis command does not find the age key the way the instance keeps it:$D263"
else
    pass "every command finds the installed age key from any directory, respects an explicit one, and is handed nothing when there is none (${SCOPE263})"
fi
}
