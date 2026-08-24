# titulo: rotación: invalidar el store (fin del no-op silencioso) (W-09/R5)
# origen: verify-static.sh (v2) ══ 81
check() {
# El bug: gen_or_restore RESTAURA el .enc viejo → re-correr la fase NO rota
# (no-op silencioso para 11/14). Fix: aegis-rotate saca el .enc para que la
# fase regenere. Invariantes:
D81=""
RT="$LIBEXEC/aegis-rotate"
CL="$P/docs/protocols/rotation-checklist.md"
if [[ -f "$RT" ]]; then
    bash -n "$RT" 2>/dev/null || D81="$D81 aegis-rotate.sh no parsea;"
    [[ -x "$RT" ]] || D81="$D81 aegis-rotate.sh no ejecutable;"
    # invalida sacando el .enc del store
    grep -Eq 'rm -f "\$enc"' "$RT" || D81="$D81 no invalida el .enc del store (no rotaría);"
    grep -q 'STATE_SECRETS'     "$RT" || D81="$D81 no opera sobre el store;"
    # dry-run por defecto: solo actúa con --yes
    grep -q 'YES=0'   "$RT" || D81="$D81 no es dry-run por defecto (peligroso);"
    grep -q -- '--yes' "$RT" || D81="$D81 sin gate --yes;"
    # rechaza irreducibles (cosign invalida firmas; age es la raíz)
    grep -q 'IRREDUCIBLE' "$RT" || D81="$D81 sin guarda de irreducibles;"
    grep -q 'cosign'      "$RT" || D81="$D81 no protege cosign (regenerarlo rompe fase 80);"
else
    D81="$D81 falta init/aegis-rotate.sh;"
fi
# la doc y el código no divergen: el checklist DEBE apuntar al Paso 0
grep -q 'aegis-rotate' "$CL" 2>/dev/null \
    || D81="$D81 rotation-checklist.md no documenta el Paso 0 (invalidar el store) — el no-op vuelve;"
if [[ -n "$D81" ]]; then fail "rotacion-store:$D81"
else pass "aegis-rotate: invalida el store (dry-run+--yes), rechaza irreducibles, checklist con Paso 0"; fi
}
