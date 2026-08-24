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
#
# La cuarta clase es clase-plantilla y NO se escribe acá: se DERIVA de
# `aegis app`, que es su único dueño (_valores_de). Escribirla a mano
# sería una segunda fuente de verdad, y el día que la plantilla pida
# una cosa nueva el check mentiría en la dirección cómoda.
#
# El barrido es de TODO semilla/ y por CONTENIDO, no por extensión: el
# 2026-08-24 este check barría solo semilla/plataforma/ y solo
# yaml/yml/tf/tpl, así que las plantillas (de las que nace el repo de
# cada app: go.mod, main.go, Containerfile, README.md) no las miraba
# nadie. Es la misma ceguera por extensión del check 1.
#
# Cualquier otro __X__ = placeholder huérfano = FAIL.
DUENO_PLANTILLA="$AEGIS_ROOT/libexec/aegis-app"
if [[ ! -r "$DUENO_PLANTILLA" ]]; then
    skip "no puedo derivar clase-plantilla: falta $(basename "$DUENO_PLANTILLA")"
    return
fi
PLANTILLA="$(grep -o '"__[A-Z0-9_]\+__":' "$DUENO_PLANTILLA" \
  | tr -d '":' | sort -u)"
if [[ -z "$PLANTILLA" ]]; then
    skip "no puedo derivar clase-plantilla: $(basename "$DUENO_PLANTILLA") no declara valores de plantilla"
    return
fi
CLASE_PLANTILLA="$(printf '%s\n' $PLANTILLA | sed -e 's/^__//' -e 's/__$//' | paste -sd'|')"
ORPHANS="$(grep -rhoI '__[A-Z0-9_]\+__' "$SEMILLA" 2>/dev/null \
  | sort -u \
  | grep -v -E "^__($CLASE_PLANTILLA)__\$" \
  | grep -v -E '^__(GH_OWNER|PLATFORM_REPO|APP_REPO|ROOT_DOMAIN|REGISTRY_CLUSTER_IP|ACME_EMAIL|AEGIS_PROFILE|OBS_RETENCION_METRICAS|OBS_RETENCION_LOGS|OBS_CF_CAIDO_FOR|OBS_DEADMAN_REPEAT|AGE_PUBLIC|COSIGN_PUB|AEGIS_CA_PEM|OBS_CA_PEM|OBS_NTFY_OPERADOR_HASH|OBS_NTFY_PUENTE_HASH|CF_TUNNEL_TOKEN|SSH_PUBKEY_RSA|SSH_PUBKEY_ED25519)__$' \
  || true)"
if [[ -n "$ORPHANS" ]]; then fail "placeholders sin dueño: $ORPHANS"
else pass "placeholders: todos con dueño (config, generado, vps o plantilla — esta última derivada de $(basename "$DUENO_PLANTILLA"))"; fi
}
