# title: webhooks: HMAC RE-SINCRONIZADO en hooks existentes (corrida #10)
# origen: verify-static.sh (v2) ══ 31
check() {
# el skip por "ya existe" dejaba un hook viejo firmando con HMAC
# distinto al del store → 400 permanente en el redeliver (fase 35).
# GitHub NUNCA devuelve config.secret → no hay comparación posible;
# el fix es PATCH incondicional. Estructura exigida en el BODY de
# make_repo_webhook (líneas no-comentario): existe un `gh api -X PATCH
# ... hooks/` y ningún `return 0` ocurre ANTES del primer PATCH
# (la forma vieja del bug: existencia → return 0 sin sincronizar):
WH_BODY="$(body_of make_repo_webhook "$PHASES/15-terceros.sh" \
    | nc)"
PATCH_LN="$(echo "$WH_BODY" | grep -n -- '-X PATCH' | grep 'hooks/' | head -n1 | cut -d: -f1)"
RET0_LN="$(echo "$WH_BODY" | grep -n 'return 0' | head -n1 | cut -d: -f1)"
if [[ -z "$PATCH_LN" ]]; then
    fail "make_repo_webhook SIN gh api -X PATCH sobre hooks/ (hook existente queda con HMAC viejo → 400)"
elif [[ -n "$RET0_LN" && "$RET0_LN" -lt "$PATCH_LN" ]]; then
    fail "make_repo_webhook tiene un return 0 ANTES del PATCH (skip sin re-sincronizar — la forma del bug #10)"
else
    pass "make_repo_webhook re-sincroniza el HMAC de hooks existentes (PATCH antes de cualquier return 0)"
fi
}
