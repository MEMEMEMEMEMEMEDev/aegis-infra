# titulo: builds HABLAN al fallar y reintentan SOLO por red (F-C/F-D #15)
# origen: verify-static.sh (v2) ══ 60
check() {
D60=""
JWB="$(body_of jenkins_wait_build "$LIBS/jenkins.sh")"
# el console va en el camino FAILURE **Y** en el timeout (el diente
# reveló que un solo grep lo satisfacía el timeout solo):
(( "$(echo "$JWB" | grep -c 'consoleText')" >= 2 )) \
    || D60="$D60 jenkins_wait_build sin console en FAILURE y timeout (dos FAILURE mudos en la #15);"
JBR="$(body_of jenkins_build_retry "$LIBS/jenkins.sh")"
[[ -n "$JBR" ]] || D60="$D60 falta jenkins_build_retry;"
echo "$JBR" | grep -q 'AEGIS_NET_SIGS' \
    || D60="$D60 el retry no discrimina por firma de red (reintentaría fallos REALES);"
echo "$JBR" | grep -q 'jenkins_next_build' \
    || D60="$D60 el retry no captura next antes del POST (carrera #9);"
nc "$LIBS/common.sh" | grep -q '^AEGIS_NET_SIGS=' \
    || D60="$D60 falta AEGIS_NET_SIGS en common.sh;"
nc "$FASES/50-jenkins.sh" | grep -q 'jenkins_build_retry ci-images' \
    || D60="$D60 fase 50 no usa jenkins_build_retry para ci-images;"
if [[ -n "$D60" ]]; then fail "builds:$D60"
else pass "FAILURE imprime el console; retry SOLO con firma de red (fallo real corta ya)"; fi
}
