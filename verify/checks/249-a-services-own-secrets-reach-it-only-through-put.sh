# title: a service's own secrets (`secretos:`) are listed by the generator, and `aegis secret put` is their only door
# origin: new in v3 — 2026-09-25, the hackathon's motor needs a cloud key the platform cannot invent
check() {
# A cloud key or a chosen password is material from outside. The contract
# declares it by name; `put` encrypts it from a FILE into `data:` with the
# exact bytes, through sops's stdin, and only for a declared file. Driven
# over a fake sops that records what it was given.
D249=""
[[ -f "$AEGIS_ROOT/verify/checks/249.py" ]] || { fail "check 249 has no sidecar"; return; }
OUT249="$(python3 "$AEGIS_ROOT/verify/checks/249.py" "$AEGIS_ROOT" 2>&1)"
RC249=$?
(( RC249 == 0 )) || { fail "the scan of check 249 itself failed (rc $RC249): ${OUT249:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE249="${hit#SCOPE: }" ;;
        *)       D249="$D249 $hit;" ;;
    esac
done <<< "$OUT249"
printf '    %s\n' "${SCOPE249:-the scope was not reported}"
if [[ -n "$D249" ]]; then
    fail "a service's own secrets are mishandled:$D249"
else
    pass "secretos are listed and put is their only door: declared files only, exact bytes in data:, through stdin, never printed (${SCOPE249})"
fi
}
