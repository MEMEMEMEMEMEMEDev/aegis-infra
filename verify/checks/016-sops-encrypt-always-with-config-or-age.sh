# title: encrypting sops ALWAYS with --config or --age (pattern A)
# origin: verify-static.sh (v2) ══ 16
check() {
# sops without --config resolves .sops.yaml by CWD — and the init runs
# from init/, not from platform/ (validation #3: 3 sites broken with
# the same bug). Every encryption must go through sops_encrypt_repo /
# persist_secret (--config) or with an explicit --age (canary phase
# 10):
SOPS_BAD="$(grep -rn 'sops \(-e\|--encrypt\)' "$AEGIS_ROOT/init" "$LIBS" "$LIBEXEC" --include='*.sh' \
    | grep -v verify-static.sh \
    | nc_hits \
    | grep -v -- '--config' \
    | grep -v -- '--age ' || true)"
if [[ -n "$SOPS_BAD" ]]; then fail "encrypting sops without --config/--age (CWD-dependent):"$'\n'"$SOPS_BAD"
else pass "every sops encryption with an explicit config/recipient"; fi
}
