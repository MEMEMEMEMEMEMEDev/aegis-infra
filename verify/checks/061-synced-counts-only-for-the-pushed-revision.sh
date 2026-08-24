# title: Synced counts ONLY for the pushed revision (F-B #15)
# origin: verify-static.sh (v2) ══ 61
check() {
# the sync died from a transient DNS failure and the gate passed with
# the OLD Synced — every post-push argo_secrets_gate demands HEAD's sha:
D61=""
ASG61="$(body_of argo_secrets_gate "$LIBS/common.sh")"
echo "$ASG61" | grep -q 'expected' || D61="$D61 argo_secrets_gate without expected_sha;"
echo "$ASG61" | grep -q 'status.sync.revision' \
    || D61="$D61 does not compare against the live revision;"
for ph in 50-jenkins 70-deploy-auto 80-supply-chain 85-observability; do
    # valid anchor: rev-parse HEAD (local repo) or APP_HEAD (ls-remote
    # of the app's repo — session 21, P1.14):
    sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/$ph.sh" \
      | nc | grep 'argo_secrets_gate' \
      | grep -v 'APP_HEAD' | grep -vq 'rev-parse HEAD' 2>/dev/null \
      && D61="$D61 $ph calls argo_secrets_gate without the pushed sha;"
done
# and argo_sync re-fires on a failure with a NETWORK signature (without
# this, F-A's live errexit would kill the phase over a blink of the
# phone):
ASY61="$(body_of argo_sync "$LIBS/common.sh")"
echo "$ASY61" | grep -q 'AEGIS_NET_SIGS' \
    || D61="$D61 argo_sync does not absorb network transients (F-A makes it fatal);"
if [[ -n "$D61" ]]; then fail "staleness/transients:$D61"
else pass "secrets gates anchored to the pushed sha; argo_sync re-fires on a transient network"; fi
}
