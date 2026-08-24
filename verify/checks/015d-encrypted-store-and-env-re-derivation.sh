# title: D11 — the encrypted store and the environment re-derivation exist
# origin: verify-static.sh (v2) ══ 15, part d — split in v3
check() {
# Without a store, every re-run regenerates credentials and the
# unattended mode stops being idempotent (bug 6).
D15D=""
grep -q 'gen_or_restore' "$LIBS/secrets.sh"  || D15D="$D15D gen_or_restore missing in secrets.sh;"
grep -q 'phase_env'      "$LIBEXEC/aegis-init" || D15D="$D15D phase_env missing in aegis-init;"
if [[ -n "$D15D" ]]; then fail "store/environment:$D15D"
else pass "encrypted store + environment re-derivation present"; fi
}
