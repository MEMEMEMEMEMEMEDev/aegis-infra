# title: ninguna fase usa dpkg -i
# origen: verify-static.sh (v2) ══ 33, parte b — partida en v3
check() {
# dpkg -i no espera locks; apt-get install ./archivo.deb sí.
BAD_DPKG="$(grep -rn 'dpkg -i' "$PHASES/" | nc_hits || true)"
if [[ -n "$BAD_DPKG" ]]; then fail "dpkg -i en fases (no espera locks — usar apt-get install ./deb):"$'\n'"$BAD_DPKG"
else pass "sin dpkg -i en fases"; fi
}
