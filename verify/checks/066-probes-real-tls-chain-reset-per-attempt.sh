# title: probes: real TLS chain, reset per attempt, pins
# origin: verify-static.sh (v2) ══ 66
check() {
D66=""
# the assertions go over the PROBE'S LINES (joined), not over the whole
# phase — 'registry-tls' appears in other gates and a global grep was
# mention≠use (session 21's tooth uncovered it):
TLS66="$(sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/40-registry-pki.sh" \
  | nc | grep 'tls-probe')"
echo "$TLS66" | grep -q ' -k ' \
    && D66="$D66 registry-tls-real uses -k (it does not validate the chain — the bad cert blows up 2 phases later);"
echo "$TLS66" | grep -q 'cacert' \
    || D66="$D66 the TLS probe does not pass --cacert;"
# a bare 'registry-tls' matches the gate's NAME (registry-tls-real) —
# the anchor is the Secret's reference in the volume:
echo "$TLS66" | grep -q 'secretName.*registry-tls' \
    || D66="$D66 the TLS probe does not mount the ca.crt of the registry-tls Secret;"
# every retryable probe deletes its pod BEFORE (P1.8: --rm + retry
# cancels itself out if the attach expires and the pod stays):
for par in "40-registry-pki:dns-probe" "40-registry-pki:tls-probe" \
           "80-supply-chain:trivy-probe" "80-supply-chain:scope-probe" \
           "80-supply-chain:unsigned-probe"; do
    f="${par%%:*}"; p="${par##*:}"
    NC66="$(sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/$f.sh" | nc)"
    if echo "$NC66" | grep -q "run $p"; then
        echo "$NC66" | grep -qE "(delete pod $p .*--ignore-not-found|probe_reset [a-z-]+ $p)" \
            || D66="$D66 $f/$p without a prior delete (AlreadyExists cancels the retry);"
    fi
done
sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$AEGIS_ROOT"/init/phases/*.sh \
  | nc | grep -qE 'image=.?busybox[^:]' \
    && D66="$D66 busybox without a pin in some probe;"
if [[ -n "$D66" ]]; then fail "probes:$D66"
else pass "TLS validated against the real CA; probes reset per attempt; images pinned"; fi
}
