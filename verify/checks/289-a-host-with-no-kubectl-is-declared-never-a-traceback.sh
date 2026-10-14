# title: a host with no kubectl is declared as not evaluable, never as a traceback
# origin: new in v3 — 2026-10-13 review (M-7): on a machine without kubectl `aegis capacity` and the producer of `aegis update metrics` died with FileNotFoundError, and checks 131, 215 and 220 were red for a reason that was not the artifact's
check() {
# A cluster nobody could ask and a binary nobody installed are the same
# question to whoever reads the answer: «I could not look». The product
# already files the first as not-evaluable; this drives both commands
# with a PATH that lacks kubectl and demands a document that says why.
D289=""
[[ -f "$AEGIS_ROOT/verify/checks/289.py" ]] || { fail "check 289 has no sidecar"; return; }
OUT289="$(python3 "$AEGIS_ROOT/verify/checks/289.py" "$AEGIS_ROOT" 2>&1)"
RC289=$?
(( RC289 == 0 )) || { fail "the exercise of check 289 itself failed (rc $RC289): ${OUT289:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE289="${hit#SCOPE: }" ;;
        *)       D289="$D289 $hit;" ;;
    esac
done <<< "$OUT289"
printf '    %s\n' "${SCOPE289:-the scope was not reported}"
if [[ -n "$D289" ]]; then
    fail "a host with no kubectl gets a traceback instead of a declared third outcome:$D289"
else
    pass "without kubectl, capacity answers rc 2 with a not-evaluable step that names the missing binary, and the metrics producer still returns its document (${SCOPE289})"
fi
}
