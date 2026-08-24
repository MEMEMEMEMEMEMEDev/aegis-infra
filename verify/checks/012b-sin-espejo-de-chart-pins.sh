# titulo: los chart pins no tienen espejo en group_vars
# origen: verify-static.sh (v2) ══ 12, parte b — partida en v3
check() {
# Los pines viven en UN lugar. Un espejo en group_vars es dos verdades
# sobre la misma versión, y la que gana depende de quién corra primero.
grep -q 'chart_pins' "$P/ansible/inventory/group_vars/all.yml" \
    && fail "chart_pins resucitó en group_vars (espejo prohibido)" \
    || pass "sin espejo de chart pins en group_vars"
}
