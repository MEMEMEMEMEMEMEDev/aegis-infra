# title: resuming 80 does NOT re-build if a valid signature already exists (P1.8 in-VM)
# origin: verify-static.sh (v2) ══ 53
check() {
# every resume cost ~10 min of needless signed build:
F80_J53="$(sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$PHASES/80-supply-chain.sh" \
    | nc)"
D53=""
echo "$F80_J53" | grep -qi 'docker-content-digest' \
    || D53="$D53 the digest does not come from the registry manifest;"
echo "$F80_J53" | grep -q 'build skipped' \
    || D53="$D53 no build-skip path;"
L_SKIP="$(grep -in 'docker-content-digest' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
L_BLD="$(grep -n 'jenkins_next_build hello-aegis' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
{ [[ -n "$L_SKIP" && -n "$L_BLD" ]] && (( L_SKIP < L_BLD )); } \
    || D53="$D53 the signature-already-valid check is not BEFORE the build trigger (skip=$L_SKIP build=$L_BLD);"
echo "$F80_J53" | grep -q 'gate "firma-verificada-real"' \
    || D53="$D53 the firma-verificada-real gate disappeared (it must run ALSO on the skip);"
if [[ -n "$D53" ]]; then fail "resume idempotence:$D53"
else pass "phase 80 verifies the registry's last tag before re-building; the signature gate always runs"; fi
}
