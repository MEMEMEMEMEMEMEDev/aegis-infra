# titulo: fase 60 descompuesta por ESLABONES (Patrón B — historia #10/#11/#12)
# origen: verify-static.sh (v2) ══ 57
check() {
# el gate único push→build acoplaba edge/HMAC/scan/build y moría mudo
# con el diagnóstico en un comentario. Cada eslabón, su gate:
F60="$FASES/60-webhook.sh"
F60_NC="$(nc "$F60")"
D57=""
for g in edge-jenkins-responde hook-jenkins-registrado delivery-push-2xx \
         build-disparado-por-webhook build-webhook-verde; do
    echo "$F60_NC" | grep -q "\"$g\"" || D57="$D57 falta gate $g;"
done
# el orden ES el aislamiento: edge → delivery → scan → build:
L_A=$(grep -n '"edge-jenkins-responde"' "$F60" | head -1 | cut -d: -f1)
L_B=$(grep -n '"delivery-push-2xx"' "$F60" | head -1 | cut -d: -f1)
L_C=$(grep -n '"build-disparado-por-webhook"' "$F60" | head -1 | cut -d: -f1)
L_D=$(grep -n '"build-webhook-verde"' "$F60" | head -1 | cut -d: -f1)
{ [[ -n "$L_A" && -n "$L_B" && -n "$L_C" && -n "$L_D" ]] \
    && (( L_A < L_B && L_B < L_C && L_C < L_D )); } \
    || D57="$D57 gates fuera de orden (edge=$L_A delivery=$L_B scan=$L_C build=$L_D);"
# el gate de delivery mira el STATUS del lado GitHub (event push):
echo "$F60_NC" | grep -q 'status_code' || D57="$D57 la delivery no se valida por status_code de GitHub;"
# NEXT_MB capturado ANTES del push (carrera lastBuild #9):
L_NB=$(grep -n 'NEXT_MB=' "$F60" | head -1 | cut -d: -f1)
L_PUSH=$(grep -n 'git push' "$F60" | head -1 | cut -d: -f1)
{ [[ -n "$L_NB" && -n "$L_PUSH" ]] && (( L_NB < L_PUSH )); } \
    || D57="$D57 NEXT_MB no se captura antes del push;"
# los gates que esperan HABLAN (H7 — nada de diagnóstico-en-comentario):
for g in edge-jenkins-responde delivery-push-2xx build-disparado-por-webhook; do
    echo "$F60_NC" | grep -q "gate_diag \"$g\"" || D57="$D57 $g sin diagnóstico al fallar;"
done
if [[ -n "$D57" ]]; then fail "fase 60:$D57"
else pass "fase 60 aísla edge→delivery(status GitHub)→scan→build, cada eslabón con evidencia"; fi
}
