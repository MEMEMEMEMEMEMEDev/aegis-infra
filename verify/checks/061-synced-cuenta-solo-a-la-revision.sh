# titulo: Synced cuenta SOLO a la revisión pusheada (F-B #15)
# origen: verify-static.sh (v2) ══ 61
check() {
# el sync murió por DNS transitorio y el gate pasó con el Synced
# VIEJO — todo argo_secrets_gate post-push exige el sha de HEAD:
D61=""
ASG61="$(body_of argo_secrets_gate "$LIBS/common.sh")"
echo "$ASG61" | grep -q 'expected' || D61="$D61 argo_secrets_gate sin expected_sha;"
echo "$ASG61" | grep -q 'status.sync.revision' \
    || D61="$D61 no compara contra la revisión viva;"
for ph in 50-jenkins 70-deploy-auto 80-supply-chain 85-observability; do
    # ancla válida: rev-parse HEAD (repo local) o APP_HEAD (ls-remote
    # del repo de la app — sesión 21, P1.14):
    sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba}' "$FASES/$ph.sh" \
      | nc | grep 'argo_secrets_gate' \
      | grep -v 'APP_HEAD' | grep -vq 'rev-parse HEAD' 2>/dev/null \
      && D61="$D61 $ph llama argo_secrets_gate sin el sha pusheado;"
done
# y argo_sync re-dispara ante fallo con firma de RED (sin esto, el
# errexit vivo de F-A mataría la fase por un parpadeo del teléfono):
ASY61="$(body_of argo_sync "$LIBS/common.sh")"
echo "$ASY61" | grep -q 'AEGIS_NET_SIGS' \
    || D61="$D61 argo_sync no absorbe transitorios de red (F-A lo vuelve fatal);"
if [[ -n "$D61" ]]; then fail "staleness/transitorios:$D61"
else pass "gates de secrets anclados al sha pusheado; argo_sync re-dispara ante red transitoria"; fi
}
