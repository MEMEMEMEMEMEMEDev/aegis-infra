# titulo: D11 — el init no asume ningún gestor de secretos concreto
# origen: verify-static.sh (v2) ══ 15, parte a — partida en v3
check() {
# D11 (automatización total): el operador no tiene por qué usar el
# gestor que usó el autor. Un prompt que nombra uno concreto convierte
# una preferencia en requisito.
#
# El alcance CAMBIA en v3 y es un caso de manual: en v2 la exclusión
# era `--exclude=verify-static.sh`, por NOMBRE DE ARCHIVO. Al partir el
# verificador en 96 archivos esa exclusión dejó de excluir nada, y este
# check habría empezado a morder los comentarios de sus propios
# hermanos (H7 del registro: los filtros por nombre mueren callados
# cuando el archivo se parte). Se excluye el DIRECTORIO.
BW="$(grep -rn 'Bitwarden' "$AEGIS_ROOT/init" "$LIBS" "$LIBEXEC" \
      --exclude-dir=verify --exclude-dir=__pycache__ || true)"
if [[ -n "$BW" ]]; then fail "menciones de gestor concreto:"$'\n'"$BW"
else pass "prompts agnósticos (sin gestor asumido)"; fi
}
