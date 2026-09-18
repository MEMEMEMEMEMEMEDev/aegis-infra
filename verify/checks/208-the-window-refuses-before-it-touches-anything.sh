# title: the window refuses before it touches anything, and says every reason at once
# origin: new in v3 — 2026-09-18, a refusal that arrives after the page went up is not a refusal (plan/17)
check() {
# A REFUSAL IS ONLY A REFUSAL IF NOTHING HAPPENED YET.
#
# `aegis update window` opens with a list of reasons not to run: the
# platform repo has to be clean and pushed, the maintenance hooks have
# to be coherent, and the photo has to be takeable. Every one of those
# is a reason to stop, and all of them are worthless if the window has
# already deployed the operator's page by the time it says so.
#
# So this is not read out of the source: a fixture is built in a
# throwaway directory whose maintenance hook does one thing — create a
# file — and the window is driven at it four times. «Did it touch
# anything» then has an answer on disk instead of an argument about
# the order of the lines.
#
# The fourth situation is the one the reading of the code would have
# missed: everything passes, the window feels open, and the photo
# cannot be taken. With no before there is nothing for a rollback to
# come back TO, and the page must not go up.
D208=""
[[ -f "$LIBEXEC/aegis-update" ]] || { skip "there is no aegis update: no window to refuse"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/208.py" ]] || { fail "check 208 has no sidecar: no window was ever driven at a fixture"; return; }
command -v git >/dev/null || { skip "git is not here, and the fixture is a git repo"; return; }

OUT208="$(python3 "$AEGIS_ROOT/verify/checks/208.py" "$AEGIS_ROOT" 2>&1)"
RC208=$?
if (( RC208 != 0 )); then
    fail "the exercise of check 208 itself failed (rc $RC208) and no refusal was tested: $OUT208"
    return
fi
SCOPE208=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE208="${hit#SCOPE: }" ;;
        *)       D208="$D208 $hit;" ;;
    esac
done <<< "$OUT208"

printf '    %s\n' "${SCOPE208:-the scope was not reported}"
if [[ -n "$D208" ]]; then
    fail "the window can touch something before it refuses:$D208"
else
    pass "every reason to stop is collected in one run, and not one hook runs until they are all clear and the photo is taken ($SCOPE208)"
fi
}
