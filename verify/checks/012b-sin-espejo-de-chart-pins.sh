# title: los chart pins no tienen espejo en group_vars
# origen: verify-static.sh (v2) ══ 12, parte b — partida en v3
check() {
# Los pines viven en UN lugar. Un espejo en group_vars es dos verdades
# sobre la misma versión, y la que gana depende de quién corra primero.
# nc y no grep pelado: el comentario que EXPLICA por qué no hay
# chart_pins acá también contiene la palabra. Lo descubrió el control
# de su propio diente — mención ≠ uso, la clase de los checks 22, 25,
# 66 y 71, y ahora también de este.
nc "$P/ansible/inventory/group_vars/all.yml" | grep -q 'chart_pins' \
    && fail "chart_pins resucitó en group_vars (espejo prohibido)" \
    || pass "sin espejo de chart pins en group_vars"
}
