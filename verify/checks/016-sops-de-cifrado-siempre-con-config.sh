# title: sops de cifrado SIEMPRE con --config o --age (patrón A)
# origen: verify-static.sh (v2) ══ 16
check() {
# sops sin --config resuelve .sops.yaml por CWD — y el init corre
# desde init/, no desde platform/ (validación #3: 3 sitios rotos con
# el mismo bug). Todo cifrado debe ir vía sops_encrypt_repo /
# persist_secret (--config) o con --age explícito (canary fase 10):
SOPS_BAD="$(grep -rn 'sops \(-e\|--encrypt\)' "$AEGIS_ROOT/init" "$LIBS" "$LIBEXEC" --include='*.sh' \
    | grep -v verify-static.sh \
    | nc_hits \
    | grep -v -- '--config' \
    | grep -v -- '--age ' || true)"
if [[ -n "$SOPS_BAD" ]]; then fail "sops de cifrado sin --config/--age (CWD-dependiente):"$'\n'"$SOPS_BAD"
else pass "todo cifrado sops con config/recipient explícito"; fi
}
