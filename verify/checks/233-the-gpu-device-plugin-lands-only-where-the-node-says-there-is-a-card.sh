# title: the GPU device plugin lands only on a node labelled for a card, and phase 20 labels it by AI mode
# origin: new in v3 — 2026-09-23, the first cloud instance (AI=no) had the plugin ContainerCreating for hours and the app gpu stuck Progressing
check() {
# k8s/base/gpu ships with every instance. Its DaemonSet needs the NVIDIA
# runtime, which only exists under AI=gpu; anywhere else the pod cannot
# start and the kubelet retries forever. The nodeSelector is the switch
# and phase 20, the phase that knows AI, flips it both ways. 233.py.
D233=""
[[ -f "$AEGIS_ROOT/verify/checks/233.py" ]] || { fail "check 233 has no sidecar"; return; }
OUT233="$(python3 "$AEGIS_ROOT/verify/checks/233.py" "$AEGIS_ROOT" 2>&1)"
RC233=$?
(( RC233 == 0 )) || { fail "the scan of check 233 itself failed (rc $RC233): ${OUT233:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE233="${hit#SCOPE: }" ;;
        *)       D233="$D233 $hit;" ;;
    esac
done <<< "$OUT233"
printf '    %s\n' "${SCOPE233:-the scope was not reported}"
if [[ -n "$D233" ]]; then
    fail "the device plugin can still land where it cannot start:$D233"
else
    pass "the device plugin's DaemonSet selects aegis.dev/gpu=true, phase 20 labels the node under AI=gpu and measures it, and unlabels it otherwise with the gate declared subjectless (${SCOPE233})"
fi
}
