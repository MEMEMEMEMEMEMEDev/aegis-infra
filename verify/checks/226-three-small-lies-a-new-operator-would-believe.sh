# title: the round's rc says when it could not look, every contract's AppProject is measured, restore takes --force wherever it stands, and rotate has a help
# origin: new in v3 — 2026-09-20, closing four registro items (G-21, G-40, the positional --force, the help that printed a file header) before another person installs from main
check() {
# FOUR SMALL THINGS A NEW OPERATOR WOULD BELIEVE:
#   · `aegis check` returned 0 or 1 only and counted «COULD NOT
#     EVALUATE» with the notices: the command that runs every day said
#     «no failures» about a round that had not looked. Now 2, and 2
#     dominates 1, like every document in the house.
#   · an organization signed up after the init had its AppProject in
#     git and none in the cluster (phase 35 applies the file once, at
#     zero contracts); nothing measured it. Now the round does, per
#     contract, with the command that fixes it.
#   · `aegis state restore --force <bundle>` was silently a restore
#     WITHOUT --force: the flag was read as the second word only.
#   · `aegis rotate --help` printed the script's file header.
D226=""
[[ -f "$LIBEXEC/aegis-check" ]] || { skip "there is no aegis check"; return; }
C226="$(nc "$LIBEXEC/aegis-check")"
# the verdict: not-evaluated counted apart, and it decides first
grep -qE '^\s*noteval=0' <<< "$C226" \
    || D226="$D226 the round does not count the could-not-look notices apart from the others;"
grep -qE 'not-evaluated "\$\*"; noteval=\$\(\(noteval \+ 1\)\)' <<< "$C226" \
    || D226="$D226 a COULD NOT EVALUATE notice does not increment the round's not-evaluated count;"
verdict="$(sed -n '/^# ── verdict/,$p' "$LIBEXEC/aegis-check" | grep -vE '^\s*#')"
first_exit="$(grep -oE 'exit [0-9]' <<< "$verdict" | head -1)"
[[ "$first_exit" == "exit 2" ]] \
    || D226="$D226 the round's first exit is «${first_exit:-none}», not «exit 2»: a round that could not look does not say so first (2 dominates 1);"
grep -qE 'noteval:-0\} -gt 0' <<< "$verdict" \
    || D226="$D226 the verdict does not read the not-evaluated count;"
# every contract's AppProject
grep -qE 'kubectl get appproject "aegis-tenant-\$_o" -n argocd' <<< "$C226" \
    || D226="$D226 the round does not ask the cluster for each contract's AppProject;"
grep -qE 'appprojects-tenants.yaml' <<< "$C226" \
    || D226="$D226 the round's AppProject finding does not name the file that fixes it;"
# restore --force anywhere
R226="$LIBEXEC/state/restore"
if [[ -f "$R226" ]]; then
    grep -qE '^\s*--force\) FORCE=1' "$R226" \
        || D226="$D226 state restore does not read --force as a flag (it was the second word only);"
    grep -qE '\[\[ "\$\{2:-\}" == "--force" \]\]' "$R226" \
        && D226="$D226 state restore still reads --force positionally;"
else
    D226="$D226 there is no state restore;"
fi
# rotate has a help block the dispatcher can print
grep -qE '^# aegis-help:' "$LIBEXEC/aegis-rotate" \
    || D226="$D226 aegis rotate has no aegis-help block: --help prints the file's header;"
grep -qE '^# Usage: aegis rotate list' "$LIBEXEC/aegis-rotate" \
    || D226="$D226 aegis rotate's help does not open with its usage;"
grep -qE "sed -n '1,56p' \"\\\$0\"" "$LIBEXEC/aegis-rotate" \
    && D226="$D226 aegis rotate --help still prints the first 56 lines of its file instead of the aegis-help block;"

if [[ -n "$D226" ]]; then
    fail "a new operator would still be told something false:$D226"
else
    pass "the round exits 2 when it could not look (before 1), measures every contract's AppProject, restore reads --force anywhere, and rotate has a help"
fi
}
