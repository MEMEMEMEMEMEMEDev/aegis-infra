# title: D11 — zero manual creation in web panels in the phases
# origin: verify-static.sh (v2) ══ 15, part b — split in v3
check() {
PANEL="$(grep -rn 'profile/api-tokens\|settings/keys\|settings/tokens\|Developer settings' "$PHASES" || true)"
if [[ -n "$PANEL" ]]; then fail "web panel instructions in phases:"$'\n'"$PANEL"
else pass "zero manual creation in panels (phases)"; fi
}
