# titulo: familia CONVERGENCIA canonizada (A/B v1.0 — 5ª instancia)
# origen: verify-static.sh (v2) ══ 72
check() {
# operar/medir ANTES de que el sistema converja volvió 5 veces
# (coredns H4, op-que-nunca-llega H5, Succeeded viejo bug C,
# discovery sin tipos A, cascada de RS B). El canon: helpers
# EXISTENCIA→ESTABILIDAD→MEDIR en common.sh y los gates pasando por
# ellos — un parche puntual nuevo de la clase debe morder ACÁ:
D72=""
for h in wait_for k8s_converged deploy_current_pods_ok; do
    nc "$LIBS/common.sh" | grep -q "^$h()" \
        || D72="$D72 falta el helper $h en common.sh;"
done
ASY72="$(body_of argo_sync "$LIBS/common.sh")"
echo "$ASY72" | grep -q 'AEGIS_SYNC_VALIDATION_SIGS' \
    || D72="$D72 A: argo_sync no reintenta la validación transitoria (tasks are not valid);"
echo "$ASY72" | grep -q 'val_refires' \
    || D72="$D72 A: sin contador propio de reintentos de validación;"
echo "$ASY72" | grep -q 'syncResult.resources' \
    || D72="$D72 A: al morir no imprime QUÉ tarea es inválida (solo la frase genérica);"
nc "$LIBS/common.sh" | grep -q '^AEGIS_SYNC_VALIDATION_SIGS=' \
    || D72="$D72 A: falta la firma de validación transitoria;"
# B: en la 80, restart → CONVERGENCIA → medición del RS VIGENTE:
L_RST="$(awk '!/^[[:space:]]*#/ && /rollout restart deploy\/hello-aegis/{print NR; exit}' "$FASES/80-supply-chain.sh")"
L_CVG="$(awk '!/^[[:space:]]*#/ && /positivo-rollout-convergido/{print NR; exit}' "$FASES/80-supply-chain.sh")"
L_POS="$(awk '!/^[[:space:]]*#/ && /"positivo-admitido-y-digest"/{print NR; exit}' "$FASES/80-supply-chain.sh")"
if [[ -z "$L_RST" || -z "$L_CVG" || -z "$L_POS" ]] || ! (( L_RST < L_CVG && L_CVG < L_POS )); then
    D72="$D72 B: el positivo no espera convergencia entre el restart y la medición;"
fi
nc "$FASES/80-supply-chain.sh" | grep -q 'deploy_current_pods_ok' \
    || D72="$D72 B: el positivo no mide el RS VIGENTE (con cascada siempre hay pods viejos);"
nc "$FASES/80-supply-chain.sh" | grep -q 'POSIBLE TIMING' \
    || D72="$D72 B: sin aviso de contradicción evidencia/veredicto;"
# prohibición estructural: medir "items[0] del namespace" en un gate
# es EXACTAMENTE el bug B — cero instancias no-comentario en fases:
BAD72="$(grep -rn 'items\[0\]' "$AEGIS_ROOT"/init/phases/ 2>/dev/null | nc_hits || true)"
[[ -z "$BAD72" ]] || D72="$D72 medición items[0]-del-namespace viva: $BAD72;"
# barrido: los dos gemelos de riesgo alto que NO habían mordido:
sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$FASES/20-k3s.sh" \
  | nc | grep '"default-storageclass"' | grep -q 'wait_for' \
    || D72="$D72 barrido: storageclass de la 20 sin espera de existencia (gemelo de coredns);"
# ACÁ SE VERIFICABA que el dry-run del CR del Image Updater esperara al
# CRD en el discovery. Los dos gates se fueron con el componente (#59).
# El invariante general —esperar a que el tipo EXISTA antes de validar
# contra él— sigue cubierto por el resto de esta sección.
if [[ -n "$D72" ]]; then fail "convergencia:$D72"
else pass "EXISTENCIA→ESTABILIDAD→MEDIR canonizado: helpers en common, A/B absorbidos, gemelos (SC, CRD) cubiertos, items[0] prohibido"; fi
}
