# title: the kernel that is running still has its modules after the upgrade the product itself runs, and k3s is not the one to find out
# origin: new in v3 — 2026-09-24, lab-arch: the preflight's pacman -Syu moved linux-lts 6.18.52→6.18.53, Arch dropped the old module tree, flannel could not create its vxlan device and phase 20 died at coredns after 19 restarts of k3s; the preflight had said 29 OK
check() {
# THE PROPERTY: the measure lives in lib/host.sh and decides by the module
# tree of the RUNNING kernel (what modprobe needs), and it is asked right
# after the action that can remove it (pkg_update) in both places that
# act: the preflight (a FAIL, with the remedy) and phase 05 (a gate, so
# the init stops there and not at phase 20). Driven with a fixture tree.
D243=""
[[ -f "$AEGIS_ROOT/verify/checks/243.py" ]] || { fail "check 243 has no sidecar"; return; }
OUT243="$(python3 "$AEGIS_ROOT/verify/checks/243.py" "$AEGIS_ROOT" 2>&1)"
RC243=$?
(( RC243 == 0 )) || { fail "the scan of check 243 itself failed (rc $RC243): ${OUT243:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE243="${hit#SCOPE: }" ;;
        *)       D243="$D243 $hit;" ;;
    esac
done <<< "$OUT243"
printf '    %s\n' "${SCOPE243:-the scope was not reported}"
if [[ -n "$D243" ]]; then
    fail "a kernel replaced under the session would reach k3s unmeasured:$D243"
else
    pass "the running kernel's module tree is measured by lib/host.sh (driven: present rc 0, gone rc 1 with the remedy) and asked right after pkg_update by the preflight (FAIL) and by phase 05 (gate) (${SCOPE243})"
fi
}
