# title: an organization does not reach the GPU unless the platform hands it one
# origin: new in v3 — 2026-09-25, home instance: a tenant pod took the whole card with one env variable
check() {
# Measured in org-canary under restricted PSS with a signed image: a pod
# asking for nvidia.com/gpu was admitted, and a pod asking for nothing,
# with runtimeClassName nvidia and NVIDIA_VISIBLE_DEVICES=all, listed
# /dev/nvidia0. Neither the quota, nor PSS, nor the signature policy
# looks there. tenants-without-gpu refuses the three ways in, and the
# phases that order the signature policy must not take it with them.
D247=""
[[ -f "$AEGIS_ROOT/verify/checks/247.py" ]] || { fail "check 247 has no sidecar"; return; }
OUT247="$(python3 "$AEGIS_ROOT/verify/checks/247.py" "$AEGIS_ROOT" 2>&1)"
RC247=$?
(( RC247 == 0 )) || { fail "the scan of check 247 itself failed (rc $RC247): ${OUT247:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE247="${hit#SCOPE: }" ;;
        *)       D247="$D247 $hit;" ;;
    esac
done <<< "$OUT247"
printf '    %s\n' "${SCOPE247:-the scope was not reported}"
if [[ -n "$D247" ]]; then
    fail "an organization can reach the GPU:$D247"
else
    pass "no organization reaches the GPU: runtimeClassName, nvidia.com/gpu and NVIDIA_* are refused in org-*, and the policy survives phases 35 and 80 (${SCOPE247})"
fi
}
