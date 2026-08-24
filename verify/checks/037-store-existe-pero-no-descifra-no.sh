# title: store: 'existe pero no descifra' ≠ 'no existe' (corrida #11)
# origen: verify-static.sh (v2) ══ 37
check() {
# sops mudo (0 chars) se trataba como ausencia → el caller REGENERABA
# un secreto ya registrado en terceros (peor caso: la key cosign —
# invalidaría firmas). restore_secret debe devolver rc 2 en el caso
# no-descifra y los generadores deben pasar por store_rc_guard:
RS_BODY="$(body_of restore_secret "$LIBS/secrets.sh" \
    | nc)"
GOR_BODY="$(body_of gen_or_restore "$LIBS/secrets.sh" \
    | nc)"
GORK_BODY="$(body_of gen_or_restore_keypair "$LIBS/secrets.sh" \
    | nc)"
D37=""
echo "$RS_BODY"   | grep -q 'return 2'       || D37="$D37 restore_secret sin rc-2;"
echo "$GOR_BODY"  | grep -q 'store_rc_guard' || D37="$D37 gen_or_restore sin guard;"
echo "$GORK_BODY" | grep -q 'store_rc_guard' || D37="$D37 gen_or_restore_keypair sin guard;"
nc "$PHASES/80-supply-chain.sh" \
    | grep -q 'store_rc_guard' || D37="$D37 fase 80 (cosign) sin guard;"
if [[ -n "$D37" ]]; then fail "store no-descifra tratado como ausencia:$D37"
else pass "no-descifra = rc 2 + guard en todos los generadores (nunca regenerar sobre sops mudo)"; fi
}
