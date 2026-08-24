# title: syncs robustos + telemetría completa (P1.3/P1.11/clase G)
# origen: verify-static.sh (v2) ══ 70
check() {
D70=""
ASY70="$(body_of argo_sync "$LIBS/common.sh")"
echo "$ASY70" | grep -q 'EN VUELO' \
    || D70="$D70 argo_sync muere si selfHeal tiene una operación en curso (el patch rebota y era fallo real);"
echo "$ASY70" | grep -q 'net_refires' \
    || D70="$D70 argo_sync re-dispara por red SIN tope (la firma amplia enmascara un servicio roto);"
echo "$ASY70" | grep -q '_gate_record' \
    || D70="$D70 los syncs no dejan rastro en gates.jsonl (2 de 3 fallos reales de la corrida sin registro);"
ASG70="$(body_of argo_secrets_gate "$LIBS/common.sh")"
echo "$ASG70" | grep -q '_gate_record' \
    || D70="$D70 argo_secrets_gate sin registro pass/fail;"
RN70="$(body_of retry_net "$LIBS/common.sh")"
echo "$RN70" | grep -q 'delay \* 3' \
    || D70="$D70 retry_net sigue en 3×5s fijos frente a cortes de minutos (backoff ausente);"
JWB70="$(body_of jenkins_wait_build "$LIBS/jenkins.sh")"
echo "$JWB70" | grep -q 'jenkins_get_code' \
    || D70="$D70 jenkins_wait_build mapea TODO error de API a RUNNING (401/pod caído esperaban el timeout mudos);"
NB70="$(body_of jenkins_next_build "$LIBS/jenkins.sh")"
echo "$NB70" | grep -q 'retry_net' \
    || D70="$D70 jenkins_next_build sin retry ni validación (next fantasma = 1800s perdidos);"
nc "$AEGIS_ROOT"/init/phases/*.sh | grep -q 'REG_HOST="registry\.' \
    && D70="$D70 REG_HOST duplicado a mano en fases (la fuente única es REGISTRY_HOST_INTERNAL);"
nc "$LIBS/common.sh" | grep -q '^REGISTRY_HOST_INTERNAL=' \
    || D70="$D70 falta REGISTRY_HOST_INTERNAL en common.sh;"
nc "$PHASES/40-registry-pki.sh" | grep -q 'clusterip-coincide-con-el-service' \
    || D70="$D70 REGISTRY_CLUSTER_IP jamás se valida contra el Service real;"
if [[ -n "$D70" ]]; then fail "syncs/telemetría:$D70"
else pass "selfHeal adoptado, backoff real, 404≠API-rota, gates.jsonl completo, registry con fuente única validada"; fi
}
