# title: el cleanup de secretos no usa rmdir
# origen: verify-static.sh (v2) ══ 30, parte b — partida en v3
check() {
# rmdir falla con subdirectorios (docker/) → la fase queda FALLIDA con
# el trabajo hecho, que es el peor desenlace posible (corrida #9).
if nc "$LIBS/secrets.sh" | grep -q 'rmdir'; then
    fail "secrets.sh usa rmdir (falla con subdirs tipo docker/ — usar rm -rf post-shred)"
else
    pass "secrets_cleanup sin rmdir (rm -rf post-shred)"
fi
}
