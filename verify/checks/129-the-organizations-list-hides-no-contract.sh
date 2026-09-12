# title: the organizations list shows every contract, the ones that validate and the ones that do not
# origin: new in v3 — 2026-09-11, `aegis org list` is the console's entry screen (plan/11 §A2)
check() {
# THE ENTRY SCREEN OF THE CONSOLE IS THIS LIST, and the worst shape it
# could take is a silent filter.
#
# An organization whose contract stops validating does not stop
# existing: its namespace is there, its pods are running, its hostname
# is serving. If the list quietly drops it, the screen looks TIDIER than
# the instance, and nobody goes looking for what is missing from a list
# that looks complete. A wrong entry gets noticed; an absent one does
# not.
#
# So the command lists it anyway, marked as `wrong` and carrying the
# validator's own message, and the document's rc says so too.
#
# The check is behavioural: it builds a tree with one contract that
# validates and one that does not, runs the real command against it in
# tmpfs, and reads the document. Nothing is created, nothing is deleted,
# and no cluster is contacted — the command writes nothing by design.
D129=""
[[ -f "$LIBS/aegis/org.py" ]] || { skip "there is no generator: nothing lists organizations"; return; }
grep -q '"list"' <<<"$(nc "$LIBS/aegis/org.py")" || { skip "aegis org has no `list` verb yet: this check has no subject"; return; }

OUT129="$(python3 "$AEGIS_ROOT/verify/checks/129.py" "$AEGIS_ROOT" 2>&1)"
RC129=$?
if (( RC129 != 0 )); then
    fail "the exercise of check 129 itself failed (rc $RC129) and the list was never measured: $OUT129"
    return
fi
SCOPE129=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE129="${hit#SCOPE: }" ;;
        *)       D129="$D129 $hit;" ;;
    esac
done <<< "$OUT129"

printf '    %s\n' "${SCOPE129:-the scope was not reported}"
if [[ -n "$D129" ]]; then
    fail "the organizations list is tidier than the instance:$D129"
else
    pass "every contract is listed, the broken one is named and marked, and the rc says so ($SCOPE129)"
fi
}
