# title: what a backup or a restore stages in the clear dies with the call, overwritten, however the call ends
# origin: new in v3 — 2026-10-13 review (A-9): aegis data staged the dumps under /tmp and removed them with rmtree in a finally that a TERM never runs; aegis state backup|restore staged under /tmp with a plain rm -rf, on EXIT only
check() {
D286=""
[[ -f "$AEGIS_ROOT/verify/checks/286.py" ]] || { fail "check 286 has no sidecar"; return; }
OUT286="$(python3 "$AEGIS_ROOT/verify/checks/286.py" "$AEGIS_ROOT" 2>&1)"
RC286=$?
(( RC286 == 0 )) || { fail "the exercise of check 286 itself failed (rc $RC286): ${OUT286:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE286="${hit#SCOPE: }" ;;
        *)       D286="$D286 $hit;" ;;
    esac
done <<< "$OUT286"
printf '    %s\n' "${SCOPE286:-the scope was not reported}"
if [[ -n "$D286" ]]; then
    fail "plaintext staged by a backup or a restore can outlive the call, or leaves its blocks behind:$D286"
else
    pass "aegis data stages under the instance, overwrites before it unlinks and runs its finally on TERM/HUP; aegis state backup|restore stage in tmpfs, shred on every way out, and trap INT/TERM as well as EXIT (${SCOPE286})"
fi
}
