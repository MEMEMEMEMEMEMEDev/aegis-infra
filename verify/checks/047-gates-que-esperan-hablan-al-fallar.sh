# titulo: gates que esperan HABLAN al fallar (H7 #13)
# origen: verify-static.sh (v2) ══ 47
check() {
D47=""
# $F70_NC lo dejaba el check 46: el segundo de los cuatro acoplamientos
# de v2. `--only 47` en aquel archivo comparaba contra una variable
# vacía y pasaba en verde sin mirar nada.
F70_NC="$(nc "$FASES/70-deploy-auto.sh")"
grep -q '^gate_diag()' "$LIBS/common.sh" || D47="$D47 falta gate_diag;"
# iu-cr-vivo e iu-write-back-commit salieron con el Image Updater
# (#59); el gate que los reemplaza es pipeline-escribio-el-digest.
for g in canary-corriendo anti-loop-build-salteado pipeline-escribio-el-digest; do
    echo "$F70_NC" | grep -q "gate_diag \"$g\"" || D47="$D47 $g sin diagnóstico;"
done
# el timeout de argo_secrets_gate expone operationState.message:
ASG_BODY="$(body_of argo_secrets_gate "$LIBS/common.sh" \
    | nc)"
echo "$ASG_BODY" | grep -q 'operationState.message' \
    || D47="$D47 argo_secrets_gate muere mudo en timeout;"
if [[ -n "$D47" ]]; then fail "timeouts mudos:$D47"
else pass "gates críticos con evidencia al fallar (events/describe/operationState/console)"; fi
}
