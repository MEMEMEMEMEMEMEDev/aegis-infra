# titulo: digest ANTES del restart (carrera CR-2-poll #14)
# origen: verify-static.sh (v2) ══ 51
check() {
# tras policy-ready el deploy aún referencia el último tag PRE-firma;
# el restart inmediato produce pods denegados legítimamente. El gate
# canary-pineado-a-digest debe ir ANTES del rollout restart:
L_PIN="$(grep -n 'canary-pineado-a-digest' "$FASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
L_RST="$(grep -n 'rollout restart deploy/hello-aegis' "$FASES/80-supply-chain.sh" | head -1 | cut -d: -f1)"
if [[ -n "$L_PIN" && -n "$L_RST" ]] && (( L_PIN < L_RST )); then
    pass "fase 80 espera el bump firmado del IU (@sha256: en el deploy) antes del restart"
else
    fail "el restart del positivo corre sin esperar el digest firmado (pin=$L_PIN restart=$L_RST)"
fi
}
