# titulo: red móvil: egress con retry + rollouts pull-aware (E-1, fases 20/40)
# origen: verify-static.sh (v2) ══ 58
check() {
# la firma del operador: "se cae, lo re-tiro sin cambiar nada y
# funciona" = transitorio no absorbido o timeout calibrado para red
# buena (el pull siguió en background y quedó cacheado):
D58=""
# (a) el helper existe, con espera generosa y evidencia al timeout:
WR_BODY="$(body_of wait_rollout "$LIBS/common.sh")"
[[ -n "$WR_BODY" ]] || D58="$D58 falta wait_rollout en common.sh;"
echo "$WR_BODY" | grep -q 'get pods' || D58="$D58 wait_rollout sin evidencia de pods;"
echo "$WR_BODY" | grep -q 'get events' || D58="$D58 wait_rollout muere sin events;"
echo "$WR_BODY" | grep -q ':-900' || D58="$D58 wait_rollout sin default generoso (900s);"
# (b) todo pip install y ansible-playbook de fases lleva retry_net
# (descargas: wheels, apt, binario k3s — ansible es idempotente):
# patrones = INVOCACIONES (el guard `-x .../ansible-playbook` y el
# gate de instalación son menciones, no ejecuciones — mención ≠ uso
# aplicado al propio check):
for pat in 'pip install' 'bin/ansible-playbook.*playbooks/'; do
    BAD58="$(for ph in "$AEGIS_ROOT"/init/phases/*.sh; do
        sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$ph" | nc \
        | grep "$pat" | grep -v retry_net | sed "s|^|$(basename "$ph"): |"
    done || true)"
    [[ -n "$BAD58" ]] && D58="$D58 '$pat' sin retry_net:"$'\n'"$BAD58"
done
# (c) nadie espera coredns con rollout status directo (timeout corto
# convertía LENTO en FALLO — va por wait_rollout):
BAD58C="$(grep -rn 'rollout status deploy/coredns' "$FASES" \
    | nc_hits || true)"
[[ -n "$BAD58C" ]] && D58="$D58 coredns con rollout status directo (usar wait_rollout):"$'\n'"$BAD58C"
# (d) los probes que pullean imagen en 40 llevan retry_net:
F40_J="$(sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$FASES/40-registry-pki.sh" \
    | nc)"
for probe in tls-probe dns-probe; do
    echo "$F40_J" | grep "run $probe" | grep -vq retry_net 2>/dev/null && \
        D58="$D58 $probe sin retry_net (primer pull por red móvil);"
done
if [[ -n "$D58" ]]; then fail "red móvil:$D58"
else pass "egress de 20/40 con retry (pip/playbooks/probes); rollouts por wait_rollout con evidencia"; fi
}
