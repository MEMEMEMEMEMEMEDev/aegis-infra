# titulo: registry: leer≠vacío, digest SIEMPRE del manifest
# origen: verify-static.sh (v2) ══ 69
check() {
D69=""
nc "$FASES/70-deploy-auto.sh" | grep -q 'no pude LEER' \
    || D69="$D69 la 70 confunde 'curl falló' con 'sin tags' (gate muerto por un parpadeo);"
nc "$FASES/80-supply-chain.sh" | grep -q 'registry_last_signed_candidate' \
    || D69="$D69 la 80 sin fuente única para tag+digest del registry;"
nc "$FASES/80-supply-chain.sh" | grep -q "grep -o 'pushed digest" \
    && D69="$D69 el digest se sigue raspando del console de Jenkins (formato frágil, build equivocado en retomes);"
if [[ -n "$D69" ]]; then fail "registry:$D69"
else pass "lecturas con retry y fallo explícito; el digest sale del Docker-Content-Digest en ambos caminos"; fi
}
