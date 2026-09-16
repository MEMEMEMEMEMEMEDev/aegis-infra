# title: a plan of your own is a named step validated like the shipped ones, and the shipped ones keep their numbers
# origin: new in v3 — 2026-09-16, `aegis quota` writes the one file every ceiling comes from (plan/16 §9)
check() {
# plans.yaml argues in its own margins why a contract names a plan and
# never a number. `aegis quota` is the one command that writes that
# file, and it would be easy to make it helpful in the wrong direction:
# accept a number outside the seven, write a plan the generator later
# refuses, let a shipped plan drift on one instance, remove a plan a
# contract still names, or leave the file a little different every time
# a plan is added and removed.
#
# So the command is run for real on a copy of the seed in tmpfs and the
# FILE is what is asserted on. Nothing of the instance is touched.
D204=""
[[ -f "$LIBEXEC/aegis-quota" ]] || { skip "there is no aegis quota: nothing writes a plan"; return; }
[[ -f "$AEGIS_ROOT/verify/checks/204.py" ]] || { fail "check 204 has no sidecar: the command was never exercised"; return; }

OUT204="$(python3 "$AEGIS_ROOT/verify/checks/204.py" "$AEGIS_ROOT" 2>&1)"
RC204=$?
if (( RC204 != 0 )); then
    fail "the exercise of check 204 itself failed (rc $RC204) and no plan was written: $OUT204"
    return
fi
SCOPE204=""
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE204="${hit#SCOPE: }" ;;
        *)       D204="$D204 $hit;" ;;
    esac
done <<< "$OUT204"

printf '    %s\n' "${SCOPE204:-the scope was not reported}"
if [[ -n "$D204" ]]; then
    fail "the catalogue can be written wrong:$D204"
else
    pass "a plan added is one the generator accepts, added and removed leaves the file as it was, the shipped plans keep their numbers, and a plan a contract names stays ($SCOPE204)"
fi
}
