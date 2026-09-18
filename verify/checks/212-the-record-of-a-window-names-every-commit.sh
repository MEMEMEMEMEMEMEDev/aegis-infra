# title: the record of a window names every commit it made, and a window that changed nothing says so
# origin: new in v3 — 2026-09-18, «four commits» answers nothing at midnight (plan/17)
check() {
# A COUNT IS NOT A RECORD.
#
# The question asked about an update window is asked afterwards, by
# somebody who was not there, and it is always the same one: what did
# it change. A report that says «four commits» answers none of it — the
# next thing that person does is open one of those commits or revert it
# by hand, and for that they need the shas. `aegis update status` is
# the only place that answer lives on this instance.
#
# The third property is the one the house contract makes non-optional:
# a window that changed nothing has to say a MEASURED zero. Zero steps
# is rc 2 here, and «this window changed nothing» and «I could not tell
# you» must not look alike.
D212=""
[[ -f "$LIBEXEC/aegis-update" ]] || { skip "there is no aegis update: no window keeps a record"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/212.py" ]] || { fail "check 212 has no sidecar: no journal was ever read back"; return; }

OUT212="$(python3 "$AEGIS_ROOT/verify/checks/212.py" "$AEGIS_ROOT" 2>&1)"
RC212=$?
if (( RC212 != 0 )); then
    fail "the exercise of check 212 itself failed (rc $RC212) and no record was read: $OUT212"
    return
fi
SCOPE212=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE212="${hit#SCOPE: }" ;;
        *)       D212="$D212 $hit;" ;;
    esac
done <<< "$OUT212"

printf '    %s\n' "${SCOPE212:-the scope was not reported}"
if [[ -n "$D212" ]]; then
    fail "the record of a window is not complete:$D212"
else
    pass "every commit of the journal reaches the report and comes out of «update status», and a window that changed nothing says a measured zero ($SCOPE212)"
fi
}
