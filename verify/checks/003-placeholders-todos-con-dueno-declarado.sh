# titulo: placeholders: todos con dueño declarado
# origen: verify-static.sh (v2) ══ 3
check() {
# clase-config (dueño: render_platform_placeholders — fase 10 en
# arranque virgen y fase 85 tras traer archivos de la semilla; los 5
# de observabilidad se DERIVAN de \$PROFILE, tabla en common.sh) +
# clase-generado (dueños: fase 10 AGE_PUBLIC, fase 80
# COSIGN_PUB/AEGIS_CA_PEM, fase 85 OBS_CA_PEM y los 2 hashes bcrypt
# de ntfy) + clase-vps (dueño: bin/aegis-vps render, que arma el
# user-data del lab en /dev/shm: CF_TUNNEL_TOKEN y las dos llaves
# públicas del operador — checks 94/95).
# Cualquier otro __X__ = placeholder huérfano = FAIL.
ORPHANS="$(grep -rho '__[A-Z_]\+__' "$P" --include='*.yaml' \
    --include='*.yml' --include='*.tf' --include='*.tpl' 2>/dev/null \
  | sort -u \
  | grep -v -E '^__(GH_OWNER|PLATFORM_REPO|APP_REPO|ROOT_DOMAIN|REGISTRY_CLUSTER_IP|ACME_EMAIL|AEGIS_PROFILE|OBS_RETENCION_METRICAS|OBS_RETENCION_LOGS|OBS_CF_CAIDO_FOR|OBS_DEADMAN_REPEAT|AGE_PUBLIC|COSIGN_PUB|AEGIS_CA_PEM|OBS_CA_PEM|OBS_NTFY_OPERADOR_HASH|OBS_NTFY_PUENTE_HASH|CF_TUNNEL_TOKEN|SSH_PUBKEY_RSA|SSH_PUBKEY_ED25519)__$' \
  || true)"
if [[ -n "$ORPHANS" ]]; then fail "placeholders sin dueño: $ORPHANS"
else pass "placeholders: todos en clase-config o clase-generado"; fi
}
