# title: the console reads documents and never the prose the commands print
# origin: new in v3 — 2026-09-11, rule E-2 applied to the first consumer built on top of the CLI
check() {
# THE MISTAKE THIS FORBIDS ALREADY HAPPENED ONCE, further down.
# `aegis-app` learned whether a webhook had been CREATED —and not merely
# re-synced— by matching the sentence «webhook creado» in the
# narration. A change of wording on one side broke the table on the
# other, and the register filed it as A3. The whole --json contract of
# this etapa exists so that never repeats.
#
# The console is the first consumer built ON TOP of the CLI, and the
# cheapest wrong turn available to it is exactly that one: run a
# command, look at what it printed. It is cheap because it works, the
# first time, on a quiet machine.
#
# Two rules, and both derive their subject instead of listing it:
#   1. every aegis command the console invokes goes through
#      `cli.run_json` — never `cli.run`, which hands back the text, and
#      never a subprocess of its own;
#   2. the console's source carries none of the narration's MARKERS.
#      Which ones those are is read from `ok()`, `bad()` and `notice()`
#      in libexec/aegis-check — the functions that print them — so a
#      symbol added there tomorrow is watched without touching this
#      file.
D123=""
[[ -f "$LIBS/aegis/console.py" || -f "$LIBEXEC/aegis-console" ]] \
    || { skip "there is no console yet: nothing of it can read prose"; return; }

OUT123="$(python3 "$AEGIS_ROOT/verify/checks/123.py" "$AEGIS_ROOT" 2>&1)"
RC123=$?
if (( RC123 != 0 )); then
    fail "the sweep of check 123 itself failed (rc $RC123) and nothing was measured about how the console reads: $OUT123"
    return
fi
SCOPE123=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE123="${hit#SCOPE: }" ;;
        *)       D123="$D123 $hit;" ;;
    esac
done <<< "$OUT123"

printf '    %s\n' "${SCOPE123:-the scope was not reported}"
if [[ -n "$D123" ]]; then
    fail "the console reads prose where it should read a document:$D123"
else
    pass "the console reaches every command through cli.run_json and carries none of the narration's markers ($SCOPE123)"
fi
}
