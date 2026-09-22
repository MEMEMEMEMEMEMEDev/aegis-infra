# title: a machine aegis cannot install on is refused before anything on it is touched
# origin: new in v3 — 2026-09-22, the first install on a machine that was not Ubuntu (CachyOS) left sudoers, IPv6 and a half k3s behind
check() {
# THE ORDER IS THE PROPERTY. Refusing a non-Ubuntu host was already in
# the product: the playbook of phase 20 asserts it. What was wrong is
# WHEN: after the preflight wrote to /etc, after the wizard asked every
# question, after phase 00 warned and went on. A refusal that arrives
# after the damage is a log line, not a guard. This check wants the
# question before the first sudo, the first wizard question and the
# phase loop, and it drives the two commands on a fake CachyOS with
# sudo trapped to prove not a single one is issued (sidecar 227.py).
D227=""
[[ -f "$AEGIS_ROOT/verify/checks/227.py" ]] || { fail "check 227 has no sidecar"; return; }
OUT227="$(python3 "$AEGIS_ROOT/verify/checks/227.py" "$AEGIS_ROOT" 2>&1)"
RC227=$?
(( RC227 == 0 )) || { fail "the scan of check 227 itself failed (rc $RC227): ${OUT227:0:200}"; return; }
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    case "$hit" in
        SCOPE:*) SCOPE227="${hit#SCOPE: }" ;;
        *)       D227="$D227 $hit;" ;;
    esac
done <<< "$OUT227"
printf '    %s\n' "${SCOPE227:-the scope was not reported}"
if [[ -n "$D227" ]]; then
    fail "a machine aegis cannot install on can still be touched before it is refused:$D227"
else
    pass "the host is asked first in the preflight, the orchestrator and phase 00, with the playbook's own rule, and a CachyOS is refused with zero sudo calls (${SCOPE227})"
fi
}
