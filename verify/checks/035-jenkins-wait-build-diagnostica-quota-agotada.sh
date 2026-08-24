# titulo: jenkins_wait_build DIAGNOSTICA quota agotada (corrida #11)
# origen: verify-static.sh (v2) ══ 35
check() {
# RQ llena → el plugin no crea el pod → el build no arranca nunca y
# el wait esperaba MUDO hasta el timeout. El body del wait debe
# invocar el detector, y el detector debe mirar la evidencia real
# ('exceeded quota' en logs del controller) — no-comentario:
JW_BODY="$(body_of jenkins_wait_build "$LIBS/jenkins.sh" \
    | nc)"
JLIB_NC="$(nc "$LIBS/jenkins.sh")"
# se exige el diagnóstico PERIÓDICO dentro del loop (ventana $every),
# no solo el del timeout — el primer diente reveló que "alguna llamada
# en el body" dejaba pasar una espera muda con diagnóstico solo al final:
if echo "$JW_BODY" | grep -q '_jenkins_quota_stall "\$every"' \
   && echo "$JLIB_NC" | grep -q "grep -m1 'exceeded quota'"; then
    pass "el wait de builds detecta y reporta el stall por ResourceQuota"
else
    fail "jenkins_wait_build espera MUDO un build que la quota nunca dejará arrancar (corrida #11)"
fi
}
