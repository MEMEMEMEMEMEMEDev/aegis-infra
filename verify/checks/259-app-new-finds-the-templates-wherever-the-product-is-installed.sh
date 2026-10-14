# title: `aegis app new --template` finds the templates wherever the product is installed, side by side with the instance or around it
# origin: new in v3 — 2026-09-28, a user's instance (their H-07), reproduced 2026-09-30 on the Arch lab VM: «I cannot find the templates … this clone looks loose» on the install every guide documents
check() {
# _templates_dir() took the product to be dirname(PLATFORM_DIR), true
# only with the instance nested inside it. The sidecar LOADS the command
# and asks it in three layouts.
D259=""
[[ -f "$AEGIS_ROOT/verify/checks/259.py" ]] || { fail "check 259 has no sidecar"; return; }
OUT259="$(python3 "$AEGIS_ROOT/verify/checks/259.py" "$AEGIS_ROOT" 2>&1)"
RC259=$?
(( RC259 == 0 )) || { fail "the exercise of check 259 itself failed (rc $RC259): ${OUT259:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE259="${hit#SCOPE: }" ;;
        *)       D259="$D259 $hit;" ;;
    esac
done <<< "$OUT259"
printf '    %s\n' "${SCOPE259:-the scope was not reported}"
if [[ -n "$D259" ]]; then
    fail "aegis app new --template cannot find the templates in a layout the product installs:$D259"
else
    pass "the templates are found in the product, side by side with the instance or around it, and their absence names where it looked (${SCOPE259})"
fi
}
