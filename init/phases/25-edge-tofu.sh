#!/usr/bin/env bash
# FASE 25 — lado SaaS vía tofu (D6: SOLO Cloudflare + GitHub; cero
# recursos K8s en tofu). Produce además el Secret KSOPS del
# TUNNEL_TOKEN (el token lo emite CF; el init lo deriva por API —
# doc 26 §8.2: T2-E gris, automatizable).
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
# CR-6 reporte in-VM #14: esta fase MUTA el repo de plataforma — el
# clone local puede estar detras del remoto (fix manual del operador
# en GitHub durante un retome). Sincronizar ANTES de tocar nada:
platform_repo_sync
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/aegis.key}"

TOFU="$PLATFORM_DIR/tofu/tofu-apply.sh"
TUNNEL_ENV="$PLATFORM_DIR/tofu/envs/cloudflare-tunnel"
secrets_workdir

# (D10: el lado GitHub ya NO pasa por tofu — repos+settings B4 los
#  hizo la fase 12 y el webhook la 15, todo por gh api idempotente.
#  tofu quedó Cloudflare-only: un solo state, un solo token.)

# ── PRE-CHECK de nube sucia (corrida #5, hallazgo A) ───────────────
# El snapshot limpia la VM pero NO la nube: un tunnel homónimo de
# una corrida anterior hace que tofu falle con 409 y — peor — que
# un token inválido se cifre y recién explote 3 fases después
# (cloudflared CrashLoop). Greenfield = detectar los restos ACÁ,
# ofrecer limpiarlos (ROJO: borra en Cloudflare) y recién crear.
# Fuente única de nombre/hostnames: el main.tf del env (se parsean,
# no se duplican):
TUNNEL_NAME="$(grep -oP 'tunnel_name\s*=\s*"\K[^"]+' "$TUNNEL_ENV/main.tf")"
HOSTS="$(grep -oP 'public_hostnames\s*=\s*\[\K[^]]*' "$TUNNEL_ENV/main.tf" \
         | tr -d '" ' | tr ',' ' ')"
gate "parse-main-tf" bash -c "[[ -n '$TUNNEL_NAME' && -n '$HOSTS' ]]"
CF_API="$(restore_secret cf_api_token)" || \
    die "cf_api_token no está en el store — retomar con --from 15"
# W-03/SEC-12: token CF por config de curl en tmpfs (600), no por argv:
_cf_cfg="$SECRETS_TMP/cf_api.curlcfg"
( umask 077; printf 'header = "Authorization: Bearer %s"\n' "$(cat "$CF_API")" > "$_cf_cfg" )
_cf() { curl -sS -K "$_cf_cfg" -H 'Content-Type: application/json' "$@"; }
CFB="https://api.cloudflare.com/client/v4"
TID_PREV="$(_cf "$CFB/accounts/$CF_ACCOUNT_ID/cfd_tunnel?name=$TUNNEL_NAME&is_deleted=false" \
            | jq -r '.result[0].id // empty')"
CNAMES_PREV=()
for h in $HOSTS; do
    rid="$(_cf "$CFB/zones/$CF_ZONE_ID/dns_records?type=CNAME&name=$h.$ROOT_DOMAIN" \
           | jq -r '.result[0].id // empty')"
    [[ -n "$rid" ]] && CNAMES_PREV+=("$h.$ROOT_DOMAIN:$rid")
done
if [[ -n "$TID_PREV" || ${#CNAMES_PREV[@]} -gt 0 ]]; then
    log_warn "restos de una corrida anterior en Cloudflare (nube sucia):"
    [[ -n "$TID_PREV" ]] && log_warn "  tunnel '$TUNNEL_NAME' = $TID_PREV"
    for c in "${CNAMES_PREV[@]}"; do log_warn "  CNAME ${c%%:*}"; done
    gate_red "BORRARLOS de Cloudflare y recrear limpio (greenfield RECREA; si estos recursos fueran de OTRO proyecto, ABORTÁ)"
    if [[ -n "$TID_PREV" ]]; then
        _cf -X DELETE "$CFB/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$TID_PREV/connections" >/dev/null
        _cf -X DELETE "$CFB/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$TID_PREV" \
            | jq -e '.success == true' >/dev/null || die "no pude borrar el tunnel previo $TID_PREV"
        log_ok "tunnel previo borrado"
    fi
    for c in "${CNAMES_PREV[@]}"; do
        _cf -X DELETE "$CFB/zones/$CF_ZONE_ID/dns_records/${c##*:}" \
            | jq -e '.success == true' >/dev/null || die "no pude borrar el CNAME ${c%%:*}"
        log_ok "CNAME ${c%%:*} borrado"
    done
    # BUG 2 (corrida #6): limpiar la nube es SOLO la mitad. El
    # terraform.tfstate LOCAL sobrevive en el disco de la VM entre
    # --from 25 (git lo ignora; el disco no). Si queda, tofu hace
    # "Refreshing state" sobre el tunnel que ACABAMOS de borrar, lo da
    # por existente y hace PUT .../cfd_tunnel/<id>/configurations → 404
    # "Tunnel not found". Las DOS mitades del greenfield se limpian
    # JUNTAS: al borrar en la nube, purgar el estado local para que el
    # apply de abajo recree desde cero. (Caso clean-cloud/dirty-state
    # por borrado manual en el dashboard lo cubre el refresh de tofu:
    # remote 404 → drop del recurso → recrea.)
    rm -f "$TUNNEL_ENV/terraform.tfstate" "$TUNNEL_ENV/terraform.tfstate.backup"
    log_ok "tfstate local del env purgado — nube y estado local sincronizados"
fi

# ── cloudflare-tunnel: tunnel + config + CNAMEs ────────────────────
# apply FATAL y explícito (hallazgo A: un 409 acá envenena el token
# y el síntoma aparece 3 fases después — jamás seguir tras un error):
log_info "tofu cloudflare-tunnel (edge only)"
run_cmd "$TOFU" -chdir="$TUNNEL_ENV" init -input=false || \
    die "tofu init falló — NO seguir"
run_cmd "$TOFU" -chdir="$TUNNEL_ENV" apply -auto-approve || \
    die "tofu apply falló — NO seguir: un apply parcial deja token/CNAMEs envenenados (409 = restos en la nube; ver pre-check arriba y VALIDACION §1.8)"
# W-03/SEC-02: el tfstate tiene el TUNNEL_TOKEN y el tunnel_secret en
# claro — a 600 apenas se escribe (antes 0664, lectura por grupo/otros).
# Cifrado en reposo = deuda W-09 (decision-repos-git.md §5):
for f in "$TUNNEL_ENV"/terraform.tfstate "$TUNNEL_ENV"/terraform.tfstate.backup; do
    [[ -f "$f" ]] && chmod 600 "$f"
done

# ── TUNNEL_TOKEN → Secret KSOPS (sin pasar por pantalla) ───────────
"$TOFU" -chdir="$TUNNEL_ENV" output -raw tunnel_token \
    > "$SECRETS_TMP/tunnel_token"
gate "token-no-vacio" bash -c \
    "[[ \$(wc -c < '$SECRETS_TMP/tunnel_token') -gt 50 ]]"
# validación REAL del token ANTES de cifrarlo (hallazgo A: el token
# inválido recién explotaba en el CrashLoop de cloudflared, fase 35).
# El connector token es base64(JSON{a,t,s}); debe apuntar a ESTA
# cuenta y al tunnel que ESTE apply creó (shape-check estructural,
# sin imprimir el secreto):
TUNNEL_ID="$("$TOFU" -chdir="$TUNNEL_ENV" output -raw tunnel_id)"
gate "token-apunta-al-tunnel-nuevo" bash -c \
  "base64 -d < '$SECRETS_TMP/tunnel_token' 2>/dev/null \
   | jq -e --arg a '$CF_ACCOUNT_ID' --arg t '$TUNNEL_ID' \
       '.a == \$a and .t == \$t and (.s | length > 0)' >/dev/null"
make_enc_secret cloudflared-tunnel-token infra-edge \
    "$PLATFORM_DIR/k8s/base/ingress/cloudflare-tunnel/secret-cloudflared-tunnel-token.enc.yaml" \
    "TUNNEL_TOKEN=$SECRETS_TMP/tunnel_token"

# ── SERVICE TOKEN DE ACCESS → store (#87/#88) ─────────────────────
# El mismo apply de arriba levanta Cloudflare Access delante de
# argocd.<dom> y jenkins.<dom> (module.access, #76). Eso deja a las
# fases 35 y 60 sondeando hostnames que ahora contestan 302 al login
# de Cloudflare — y ese 302 lo sirve el borde, sin entrar al túnel.
# La 35 lo aceptaba como "edge-responde" (verde con el cluster
# apagado) y la 60 lo rechazaba (rojo sobre un Jenkins sano). Las dos
# necesitan atravesar Access, y para eso necesitan ESTO.
#
# NO va a un Secret de K8s: nadie DENTRO del cluster lo usa. Vive en
# el store porque los consumidores son el propio init (fases 35/60) y
# aegis-rotate --verificar — los dos corren en la máquina del
# operador y los dos tienen la age key. Mandarlo al cluster sería
# repartir una credencial a un lugar que no la necesita.
#
# Hasta hoy estos dos valores los había puesto una mano en #76: una
# instancia nueva llegaba a la 35 sin ellos y el gate mentía.
# Los dos persist_secret van LITERALES y no en un for. El check 89 de
# verify-static.sh extrae los nombres del store parseando estas
# llamadas, y su punto ciego declarado es exactamente
# `persist_secret "$variable"`: un bucle acá dejaría dos credenciales
# nuevas fuera del inventario de rotación sin que nada avisara. Dos
# líneas repetidas cuestan menos que un punto ciego.
( umask 077
  "$TOFU" -chdir="$TUNNEL_ENV" output -raw access_service_token_client_id \
      > "$SECRETS_TMP/access_st_id"
  "$TOFU" -chdir="$TUNNEL_ENV" output -raw access_service_token_client_secret \
      > "$SECRETS_TMP/access_st_secret" )
# shape-check de LARGO, no de formato: la forma del client_id
# (`<uuid>.access`) la define Cloudflare, y atar un gate a ella es
# C15. Vacío sí es fallo duro — significa que module.access no se
# aplicó, y entonces Access no está puesto:
gate "access-st-id-no-vacio" bash -c \
    "[[ \$(wc -c < '$SECRETS_TMP/access_st_id') -gt 20 ]]"
gate "access-st-secret-no-vacio" bash -c \
    "[[ \$(wc -c < '$SECRETS_TMP/access_st_secret') -gt 20 ]]"
persist_secret access_st_id     "$SECRETS_TMP/access_st_id"
persist_secret access_st_secret "$SECRETS_TMP/access_st_secret"
log_ok "service token de Access persistido al store — las fases 35 y 60 pueden atravesarlo"

# CASO BORDE (Q2): si este apply RECREÓ un tunnel previo, pueden
# quedar CNAMEs/registros huérfanos del anterior. tofu es dueño de
# los suyos; los ajenos se limpian a mano. El gate de DNS es en la
# fase 35 (cuando haya backend que responda).

# ── commit de los cifrados de las fases 15+25 al repo ──────────────
log_info "commit de secrets cifrados + tfvars al repo de plataforma"
# clase F auditoría: sin || true — staged vacío es no-op legítimo,
# un commit FALLIDO con cambios staged mata la fase acá (no 2 después):
git_commit_if_changes "$PLATFORM_DIR" \
    "feat(bootstrap): secrets cifrados iniciales + edge aplicado"
# push de los cifrados nuevos (el remoto existe y está sembrado
# desde la fase 12). BLOQUEANTE: todo lo que sigue (ArgoCD, KSOPS)
# lee del remoto — sin push, fases posteriores contra repo viejo.
run_cmd retry_net 3 git -C "$PLATFORM_DIR" push -u origin main || \
  die "push falló — verificar remoto/deploy key y retomar con --from 25"

log_ok "Edge aplicado: repo GitHub configurado, tunnel vivo (503 \
inofensivo hasta Traefik — la espera es normal), token cifrado"
