# title: a Kyverno restart owed for the registry CA is measured (pod older than its CA ConfigMap), not remembered by the run that injected it
# origin: new in v3 — 2026-09-24, second cloud VM: the run that injected the CA died before the restart, and the signed canary was denied over plain HTTP
check() {
# Kyverno mounts the registry CA by subPath, which the kubelet never
# refreshes: a controller running when the CA lands keeps the old file
# until it is restarted. Phase 80 restarted it only on the run that
# injected the CA. That run can die before the restart (the second cloud
# VM's did, in mirror-images), and every later run sees the CA already in
# git and restarts nothing. The debt has to be read off the cluster.
D236=""
[[ -f "$AEGIS_ROOT/verify/checks/236.py" ]] || { fail "check 236 has no sidecar"; return; }
OUT236="$(python3 "$AEGIS_ROOT/verify/checks/236.py" "$AEGIS_ROOT" 2>&1)"
RC236=$?
(( RC236 == 0 )) || { fail "the scan of check 236 itself failed (rc $RC236): ${OUT236:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE236="${hit#SCOPE: }" ;;
        *)       D236="$D236 $hit;" ;;
    esac
done <<< "$OUT236"
printf '    %s\n' "${SCOPE236:-the scope was not reported}"
if [[ -n "$D236" ]]; then
    fail "a Kyverno controller can keep a CA it never loaded:$D236"
else
    pass "phase 80 restarts every Kyverno controller whose pods are older than the CA they mount, whichever run injected it, and gates that none is left behind (${SCOPE236})"
fi
}
