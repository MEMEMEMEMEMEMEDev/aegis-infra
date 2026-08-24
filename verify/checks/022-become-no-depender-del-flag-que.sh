# title: become: NO depender del flag que ansible ignora (bug 1)
# origen: verify-static.sh (v2) ══ 22
check() {
# Corrida #6, bug 1: --become-password-file estaba "verificado contra
# el source" pero become lo IGNORÓ en vivo (timeout de sudo prompt) —
# clase verificado-vs-fuente≠probado. El único camino probado es
# NOPASSWD. El setup NO debe volver a apoyarse en ese flag ni pasar el
# password por argv; debe validar el drop-in con visudo:
BECOME_LIB="$LIBS/common.sh"
BECOME_BAD=""
# el flag SÍ se nombra en el comentario que explica por qué NO se usa
# (documentar la deuda es legítimo) — se mira USO real, no menciones:
# líneas no-comentario. Sin esto el check se caza su propio comentario
# (clase check 15/18b: la mención textual no es el uso):
nc "$BECOME_LIB" | grep -q 'become-password-file' \
    && BECOME_BAD="$BECOME_BAD reaparece --become-password-file en USO (flag ignorado en vivo);"
grep -q 'visudo -cf' "$BECOME_LIB" \
    || BECOME_BAD="$BECOME_BAD falta validación visudo del drop-in NOPASSWD;"
# el password NUNCA a argv de sudo (--stdin/-S sí; -p con el valor no):
grep -qE 'sudo .*-S' "$BECOME_LIB" \
    || BECOME_BAD="$BECOME_BAD el password no va por stdin de sudo (-S);"
if [[ -n "$BECOME_BAD" ]]; then fail "become_setup:$BECOME_BAD"
else pass "become_setup: camino NOPASSWD probado (visudo + -S), sin el flag ignorado"; fi
}
