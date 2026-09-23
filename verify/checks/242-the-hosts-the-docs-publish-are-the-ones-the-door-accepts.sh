# title: the host families the docs publish are the ones the door accepts, and every name they use is driven through the door
# origin: new in v3 — 2026-09-23, the distro line: three documents say in words what lib/host.sh decides, and nothing made them move together
check() {
# Check 200 crosses the disk requirement between the READMEs and the
# preflight; this crosses the HOST. The rule is AEGIS_HOST_SUPPORTED_DEFAULT
# plus the minimum per family (lib/host.sh). The Host row of README.md,
# README.en.md and the requirements table of the your-machine journey
# have to promise exactly that, and each name they use is turned into
# an os-release and driven through host_supported: what they promise
# is let in, what they list as refused is refused.
D242=""
[[ -f "$AEGIS_ROOT/verify/checks/242.py" ]] || { fail "check 242 has no sidecar"; return; }
OUT242="$(python3 "$AEGIS_ROOT/verify/checks/242.py" "$AEGIS_ROOT" 2>&1)"
RC242=$?
(( RC242 == 0 )) || { fail "the scan of check 242 itself failed (rc $RC242): ${OUT242:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE242="${hit#SCOPE: }" ;;
        *)       D242="$D242 $hit;" ;;
    esac
done <<< "$OUT242"
printf '    %s\n' "${SCOPE242:-the scope was not reported}"
if [[ -n "$D242" ]]; then
    fail "the docs and the door disagree about which machines aegis installs on:$D242"
else
    pass "the READMEs and the journey publish the door's families and minimums, and every name they use answers as promised (${SCOPE242})"
fi
}
