# title: no reading is drawn without saying when it was taken
# origin: new in v3 — 2026-09-11, `aegis console serve` measures once and then serves what it has
check() {
# THE OLDEST LIE A DASHBOARD TELLS is not a wrong number. It is a RIGHT
# number from forty minutes ago, shown as if it were now. An error
# looks like an error; a stale measurement looks exactly like a fresh
# one, and somebody acts on it.
#
# `aegis console serve` makes that possible on purpose: the round takes
# about a minute, so the console reads once, serves what it has, and
# reads again when asked. That is the right shape — a page that
# re-measured on every refresh would hammer the cluster — and it is
# only honest if every source says WHEN it was read.
#
# Two things are asked, and the second is the one that matters to a
# person: the age is in the attribute, and it is ON THE PAGE. An
# operator reads the page, not the DOM.
#
# And when there is no time to show, the console says so rather than
# leaving the line out: an absent age is a question nobody asked.
D127=""
[[ -f "$LIBS/aegis/console.py" ]] || { skip "there is no renderer yet: nothing draws a reading"; return; }
[[ -d "$AEGIS_ROOT/console/cases" ]] || { skip "there is no corpus to render: this check has no subject"; return; }

OUT127="$(python3 "$AEGIS_ROOT/verify/checks/127.py" "$AEGIS_ROOT" 2>&1)"
RC127=$?
if (( RC127 != 0 )); then
    fail "the renderer of check 127 itself failed (rc $RC127) and no age was measured: $OUT127"
    return
fi
SCOPE127=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE127="${hit#SCOPE: }" ;;
        *)       D127="$D127 $hit;" ;;
    esac
done <<< "$OUT127"

printf '    %s\n' "${SCOPE127:-the scope was not reported}"
if [[ -n "$D127" ]]; then
    fail "the console draws a measurement without its age:$D127"
else
    pass "every source the console draws carries when it was read, in the attribute and on the page ($SCOPE127)"
fi
}
