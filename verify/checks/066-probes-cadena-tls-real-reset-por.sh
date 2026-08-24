# titulo: probes: cadena TLS real, reset por intento, pins
# origen: verify-static.sh (v2) ══ 66
check() {
D66=""
# las aserciones van sobre las LÍNEAS DEL PROBE (joined), no sobre
# la fase entera — 'registry-tls' aparece en otros gates y un grep
# global era mención≠uso (el diente de la sesión 21 lo destapó):
TLS66="$(sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$FASES/40-registry-pki.sh" \
  | nc | grep 'tls-probe')"
echo "$TLS66" | grep -q ' -k ' \
    && D66="$D66 registry-tls-real usa -k (no valida la cadena — el cert malo explota 2 fases después);"
echo "$TLS66" | grep -q 'cacert' \
    || D66="$D66 el probe TLS no pasa --cacert;"
# 'registry-tls' pelado matchea el NOMBRE del gate (registry-tls-real)
# — el ancla es la referencia del Secret en el volumen:
echo "$TLS66" | grep -q 'secretName.*registry-tls' \
    || D66="$D66 el probe TLS no monta el ca.crt del Secret registry-tls;"
# todo probe reintentable borra su pod ANTES (P1.8: --rm + retry se
# auto-anula si el attach vence y el pod queda):
for par in "40-registry-pki:dns-probe" "40-registry-pki:tls-probe" \
           "80-supply-chain:trivy-probe" "80-supply-chain:scope-probe" \
           "80-supply-chain:unsigned-probe"; do
    f="${par%%:*}"; p="${par##*:}"
    NC66="$(sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$FASES/$f.sh" | nc)"
    if echo "$NC66" | grep -q "run $p"; then
        echo "$NC66" | grep -qE "(delete pod $p .*--ignore-not-found|probe_reset [a-z-]+ $p)" \
            || D66="$D66 $f/$p sin delete previo (AlreadyExists anula el retry);"
    fi
done
sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$AEGIS_ROOT"/init/phases/*.sh \
  | nc | grep -qE 'image=.?busybox[^:]' \
    && D66="$D66 busybox sin pin en algún probe;"
if [[ -n "$D66" ]]; then fail "probes:$D66"
else pass "TLS validado contra el CA real; probes con reset por intento; imágenes pinneadas"; fi
}
