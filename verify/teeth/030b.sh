# dientes del check 030b (el cleanup de secretos no usa rmdir)
# rmdir falla con subdirectorios (docker/): la fase queda FALLIDA con
# el trabajo hecho, que es el peor desenlace.
rojo_1() { printf '\n_limpieza_mala() { rmdir "$TMPDIR"; }\n' >> "$AEGIS_ROOT/lib/secrets.sh"; }
