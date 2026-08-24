# titulo: greenfield: al limpiar la nube, purgar el tfstate LOCAL
# origen: verify-static.sh (v2) ══ 21
check() {
# Corrida #6, bug 2: el pre-check de nube sucia borra el tunnel de
# Cloudflare pero el terraform.tfstate local sobrevive en el disco de
# la VM entre --from 25 → tofu lo da por existente y hace PUT
# configurations → 404. Las dos mitades del greenfield se limpian
# JUNTAS. Estático: el bloque de limpieza de la fase 25 DEBE purgar el
# tfstate del env (rm de terraform.tfstate) — no basta con borrar en la
# nube. Se exige la co-ocurrencia en el mismo archivo:
P25="$FASES/25-edge-tofu.sh"
if grep -q 'cfd_tunnel/\$TID_PREV' "$P25" \
   && grep -qE 'rm -f .*\$TUNNEL_ENV/terraform\.tfstate' "$P25"; then
    pass "fase 25: la limpieza de nube purga también el tfstate local"
else
    fail "fase 25 borra en la nube pero NO purga el tfstate local (bug 2: nube y estado desincronizados)"
fi
}
