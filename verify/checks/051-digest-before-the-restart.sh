# title: digest BEFORE the restart (CR-2-poll race #14)
# origin: verify-static.sh (v2) ══ 51
check() {
# after policy-ready the deploy still references the last PRE-signature
# tag; an immediate restart produces legitimately denied pods. The
# canary-pineado-a-digest gate must come BEFORE the rollout restart:
L_PIN="$(grep -n 'canary-pineado-a-digest' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
L_RST="$(grep -n 'rollout restart deploy/hello-aegis' "$PHASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
if [[ -n "$L_PIN" && -n "$L_RST" ]] && (( L_PIN < L_RST )); then
    pass "phase 80 waits for the IU's signed bump (@sha256: in the deploy) before the restart"
else
    fail "the positive's restart runs without waiting for the signed digest (pin=$L_PIN restart=$L_RST)"
fi
}
