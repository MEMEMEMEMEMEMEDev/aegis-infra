# title: no phase uses dpkg -i
# origin: verify-static.sh (v2) ══ 33, part b — split in v3
check() {
# dpkg -i does not wait for locks; apt-get install ./file.deb does.
BAD_DPKG="$(grep -rn 'dpkg -i' "$PHASES/" | nc_hits || true)"
if [[ -n "$BAD_DPKG" ]]; then fail "dpkg -i in the phases (it does not wait for locks — use apt-get install ./deb):"$'\n'"$BAD_DPKG"
else pass "no dpkg -i in the phases"; fi
}
