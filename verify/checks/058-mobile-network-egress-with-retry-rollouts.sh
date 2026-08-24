# title: mobile network: egress with retry + pull-aware rollouts (E-1, phases 20/40)
# origin: verify-static.sh (v2) ══ 58
check() {
# the operator's signature: "it falls over, I re-run it without
# changing anything and it works" = a transient not absorbed, or a
# timeout calibrated for a good network (the pull kept going in the
# background and ended up cached):
D58=""
# (a) the helper exists, with a generous wait and evidence at timeout:
WR_BODY="$(body_of wait_rollout "$LIBS/common.sh")"
[[ -n "$WR_BODY" ]] || D58="$D58 wait_rollout missing from common.sh;"
echo "$WR_BODY" | grep -q 'get pods' || D58="$D58 wait_rollout without pod evidence;"
echo "$WR_BODY" | grep -q 'get events' || D58="$D58 wait_rollout dies without events;"
echo "$WR_BODY" | grep -q ':-900' || D58="$D58 wait_rollout without a generous default (900s);"
# (b) every pip install and ansible-playbook in the phases carries
# retry_net (downloads: wheels, apt, the k3s binary — ansible is
# idempotent): patterns = INVOCATIONS (the `-x .../ansible-playbook`
# guard and the install gate are mentions, not executions — mention ≠
# use, applied to the check itself):
for pat in 'pip install' 'bin/ansible-playbook.*playbooks/'; do
    BAD58="$(for ph in "$AEGIS_ROOT"/init/phases/*.sh; do
        sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$ph" | nc \
        | grep "$pat" | grep -v retry_net | sed "s|^|$(basename "$ph"): |"
    done || true)"
    [[ -n "$BAD58" ]] && D58="$D58 '$pat' without retry_net:"$'\n'"$BAD58"
done
# (c) nobody waits for coredns with a direct rollout status (a short
# timeout turned SLOW into FAILURE — it goes through wait_rollout):
BAD58C="$(grep -rn 'rollout status deploy/coredns' "$PHASES" \
    | nc_hits || true)"
[[ -n "$BAD58C" ]] && D58="$D58 coredns with a direct rollout status (use wait_rollout):"$'\n'"$BAD58C"
# (d) the probes in phase 40 that pull an image carry retry_net:
F40_J="$(sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/40-registry-pki.sh" \
    | nc)"
for probe in tls-probe dns-probe; do
    echo "$F40_J" | grep "run $probe" | grep -vq retry_net 2>/dev/null && \
        D58="$D58 $probe without retry_net (first pull over a mobile network);"
done
if [[ -n "$D58" ]]; then fail "mobile network:$D58"
else pass "egress of 20/40 with retry (pip/playbooks/probes); rollouts through wait_rollout with evidence"; fi
}
