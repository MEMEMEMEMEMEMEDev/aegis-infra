# titulo: gates de Jenkins SIN /wfapi/ (H3 #13 — plugin no instalado)
# origen: verify-static.sh (v2) ══ 42
check() {
# /wfapi/ lo provee pipeline-stage-view (NO instalado; los stage-STEP
# y stage-tags-metadata son OTROS plugins) → 404 eterno con el
# sistema funcionando. Los gates van por el core (/api/json) y el
# console del build:
BAD42="$(grep -rn '/wfapi/' "$FASES" "$AEGIS_ROOT/init/lib" \
    | nc_hits || true)"
AL_BODY="$(body_of _antiloop_skipped "$FASES/70-deploy-auto.sh" \
    | nc)"
D42=""
[[ -n "$BAD42" ]] && D42="$D42 uso de /wfapi/:"$'\n'"$BAD42"
echo "$AL_BODY" | grep -q '/api/json' \
    && echo "$AL_BODY" | grep -q 'skipped due to when conditional' \
    || D42="$D42 _antiloop_skipped no valida por core+console;"
if [[ -n "$D42" ]]; then fail "wfapi:$D42"
else pass "cero /wfapi/; anti-loop validado por /api/json + console (endpoint del core)"; fi

# ACÁ ESTABA el check 43: el CR del Image Updater contra el schema real
# del CRD, con dry-run=server. Se fue con el componente en #59.
#
# La LECCIÓN que lo motivó no se pierde y vale más que el check: el CR
# original estaba escrito contra un schema IMAGINARIO —campos que no
# existían en ninguna parte del CRD— y ArgoCD reintentaba el apply
# infinito con el error escondido en operationState. De ahí salió la
# regla FUENTE-ES-BINARIO: un manifiesto se valida contra el esquema
# VIVO, no contra lo que uno cree que acepta. Sigue aplicando a
# cualquier CR que se agregue mañana.
}
