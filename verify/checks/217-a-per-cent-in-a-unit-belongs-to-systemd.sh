# title: a per cent in a unit file belongs to systemd, so the shell's must be escaped
# origin: new in v3 — 2026-09-20, `printf "%s"` reached /bin/sh as `printf "/bin/bash"` and a timer went green with nothing stored
check() {
# THE UNIT SAID IT WORKED AND NOTHING ARRIVED.
#
# On 2026-09-20 the update timer piped its measurement into curl with
# `printf "%s" "$m"`. In a unit file `%` opens a systemd SPECIFIER, and
# `%s` is the user's login shell, so what reached /bin/sh was
#
#     printf "/bin/bash" "$m"
#
# which prints nine characters and drops the measurement. curl posted
# them, VictoriaMetrics answered 204, and the unit finished 0/SUCCESS.
# The timer reported «26 series: 33 behind», the panel stayed empty, and
# nothing anywhere went red.
#
# That is this product's own disease —a green that means «I did not
# look»— in the timer of the command written to cure it. So: every `%`
# in a directive is escaped, or it is one of the specifiers this
# artifact uses on purpose, and the list of those lives in the check
# because it is a policy and not a fact about the files.
#
# Comments are stripped first. The unit that caused this now spells the
# trap out in its own comment, per cents and all, and a check that read
# prose as code would go red on the explanation — filed six times in
# this repo already.
D217=""
[[ -d "$AEGIS_ROOT/share/systemd" ]] || { skip "this artifact ships no systemd units"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/217.py" ]] || { fail "check 217 has no sidecar: no unit was read"; return; }

OUT217="$(python3 "$AEGIS_ROOT/verify/checks/217.py" "$AEGIS_ROOT" 2>&1)"
RC217=$?
if (( RC217 != 0 )); then
    fail "the exercise of check 217 itself failed (rc $RC217): $OUT217"
    return
fi
SCOPE217=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE217="${hit#SCOPE: }" ;;
        *)       D217="$D217 $hit;" ;;
    esac
done <<< "$OUT217"

printf '    %s\n' "${SCOPE217:-the scope was not reported}"
if [[ -n "$D217" ]]; then
    fail "systemd would rewrite a command line before it ever runs:$D217"
else
    pass "every per cent in every shipped unit is escaped or is a specifier this artifact asks for on purpose ($SCOPE217)"
fi
}
