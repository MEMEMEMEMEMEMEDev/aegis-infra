# title: ningún echo de UI a stdout en las libs
# origen: verify-static.sh (v2) ══ 14, parte b — partida en v3
check() {
# Los saltos de línea tras `read -rsp` contaminaban el valor retornado.
# El alcance se amplía en v3: las libs ya no viven bajo init/, y
# libexec/ también tiene funciones que otros capturan con $().
UI_BAD="$(grep -rn '; echo$\|; echo "' "$LIBS" | grep -v '>&2' || true)"
if [[ -n "$UI_BAD" ]]; then fail "echo de UI sin >&2 en libs:"$'\n'"$UI_BAD"
else pass "sin echo de UI a stdout en libs"; fi
}
