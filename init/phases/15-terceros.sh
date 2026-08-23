#!/usr/bin/env bash
# FASE 15 — credenciales de terceros, AUTOMÁTICAS (D11).
#
# FILOSOFÍA (rediseño post-corrida #2): la fricción manual NO es
# seguridad. CERO navegador, CERO archivos que el operador mueva,
# CERO tokens creados a mano en paneles. Lo que esta fase pide al
# humano: pegar UNA credencial maestra de Cloudflare (efímera: se
# usa para acuñar los tokens acotados y se destruye de tmpfs). Todo
# lo demás — deploy keys, webhooks, credencial de CI, tokens
# acotados — lo hace el init por API/CLI.
#
# La GitHub App fue REEMPLAZADA (D11): crearla sin navegador no
# existe (manifest flow exige redirect web) y acuñar PATs por API
# tampoco — la credencial de CI es el token de la sesión gh
# (`gh auth token`), con su trade-off documentado en
# docs/protocols/github-credential.md.
#
# Idempotencia (bug 6): todo secreto generado va al store cifrado
# (gen_or_restore) — un --from acá REUTILIZA, no regenera.
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
secrets_workdir

TOKENS_DIR="$PLATFORM_DIR/tofu/secrets"
B="$PLATFORM_DIR/k8s/base"

# ═══ 15.1 Cloudflare: UNA maestra efímera → tokens acotados ═══════
# El operador NO crea tokens en el dash. Pega su credencial maestra
# (Global API Key, o un token de cuenta con "Account API Tokens:
# Edit"); el init acuña los 2 acotados vía la API de account-owned
# tokens y shred-ea la maestra.
# Los acotados se persisten cifrados (re-run no vuelve a pedir nada).
_cf_call() {   # _cf_call <method> <path> [json-payload-file]
    local method="$1" path="$2" payload="${3:-}"
    # W-03/SEC-12: la maestra CF NO va por argv (/proc/PID/cmdline). El
    # header con el secreto va a un config de curl en tmpfs (600) por -K,
    # igual que el netrc-por-archivo de jenkins.sh. X-Auth-Email no es
    # secreto y puede seguir en argv.
    local cfg="$SECRETS_TMP/cf.curlcfg"
    ( umask 077
      if [[ "$CF_AUTH_MODE" == "key" ]]; then
          printf 'header = "X-Auth-Key: %s"\n' "$(cat "$CF_MASTER")" > "$cfg"
      else
          printf 'header = "Authorization: Bearer %s"\n' "$(cat "$CF_MASTER")" > "$cfg"
      fi )
    local args=(-sS -K "$cfg" -X "$method" \
                "https://api.cloudflare.com/client/v4$path" \
                -H "Content-Type: application/json")
    [[ "$CF_AUTH_MODE" == "key" ]] && args+=(-H "X-Auth-Email: $CF_AUTH_EMAIL")
    [[ -n "$payload" ]] && args+=(--data "@$payload")
    curl "${args[@]}"
}

CF_API_FILE="$STATE_SECRETS/cf_api_token.enc"
CF_DNS_FILE="$STATE_SECRETS/cf_dns_token.enc"
# #88 (2026-08-13): el TERCER acotado. Access se aplicó a mano en #76
# porque esta fase no sabía acuñarlo, y eso significaba que una
# instancia nueva nacía con argocd y jenkins en internet abierto —
# exactamente el estado que #76 vino a cerrar, reapareciendo en cada
# instalación futura. El arreglo de una instancia no vale nada si el
# init la vuelve a parir rota.
#
# Va en la MISMA condición que los otros dos a propósito: si falta
# UNO, hay que volver a pedir la maestra igual, así que las tres se
# acuñan juntas o ninguna. Una instancia con 2 de 3 pidiendo maestra
# es correcta, no un caso de borde.
CF_ACCESS_FILE="$STATE_SECRETS/cf_access_token.enc"
if [[ -f "$CF_API_FILE" && -f "$CF_DNS_FILE" && -f "$CF_ACCESS_FILE" ]]; then
    log_info "tokens CF acotados ya en el store — sin pedir maestra (re-run)"
    CF_API="$(restore_secret cf_api_token)"
    CF_DNS="$(restore_secret cf_dns_token)"
    CF_ACCESS="$(restore_secret cf_access_token)"
else
    # P0.3 auditoría 2026-07-18 — camino por ARCHIVO (desatendido o
    # preferencia del operador): CF_MASTER_FILE apunta a la maestra
    # (idealmente en /dev/shm del lanzador). Se COPIA a nuestra tmpfs
    # y se avisa destruir el origen; el prompt queda como fallback:
    if [[ -n "${CF_MASTER_FILE:-}" ]]; then
        [[ -s "$CF_MASTER_FILE" ]] || \
            die "CF_MASTER_FILE apunta a '$CF_MASTER_FILE' y está vacío/no existe"
        install -m 600 "$CF_MASTER_FILE" "$SECRETS_TMP/cf_master"
        CF_MASTER="$SECRETS_TMP/cf_master"
        log_warn "maestra CF leída de CF_MASTER_FILE — destruí el archivo origen (shred -u) apenas termine esta fase"
    elif ni_mode; then
        die "--non-interactive sin CF_MASTER_FILE — la credencial maestra CF no puede pedirse por prompt sin operador"
    else
        printf '\nCloudflare: el init va a ACUÑAR los 2 tokens acotados\n' >&2
        printf 'por API. Necesita UNA credencial maestra, efímera (vive\n' >&2
        printf 'solo en memoria durante este paso):\n' >&2
        printf '  - tu Global API Key (37 hex), o\n' >&2
        printf '  - un API token de CUENTA con permiso\n' >&2
        printf '    "Account API Tokens: Edit".\n' >&2
        CF_MASTER="$(prompt_secret_manual 'credencial maestra CF' 30 cf_master)"
    fi
    if [[ "$(cat "$CF_MASTER")" =~ ^[0-9a-f]{37}$ ]]; then
        CF_AUTH_MODE=key
        if ni_mode; then
            CF_AUTH_EMAIL="$ACME_EMAIL"
        else
            read -rp "email de la cuenta CF [${ACME_EMAIL}]: " CF_AUTH_EMAIL \
                || die "stdin cerrado pidiendo el email de la cuenta CF"
            CF_AUTH_EMAIL="${CF_AUTH_EMAIL:-$ACME_EMAIL}"
        fi
    else
        CF_AUTH_MODE=bearer CF_AUTH_EMAIL=""
    fi
    # permission groups POR NOMBRE contra la API viva (no IDs de
    # memoria — regla fuente-es-el-binario). Si un nombre no
    # matchea, falla LISTANDO lo disponible (evidencia, no adivinar).
    # ENDPOINT /accounts/, NO /user/ (bug 1 validación #3): /user/
    # exige "user-level authentication" (error 9109) y solo la
    # Global API Key la tiene; con un token de cuenta —lo natural de
    # crear— falla. /accounts/ funciona con AMBAS credenciales:
    _cf_call GET "/accounts/$CF_ACCOUNT_ID/tokens/permission_groups" \
        > "$SECRETS_TMP/cf_pgroups.json"
    gate "cf-permission-groups" bash -c \
        "jq -e '.success == true' '$SECRETS_TMP/cf_pgroups.json' >/dev/null"
    mint_cf_token() {   # <store-name> <token-name> <python-policy-builder>
        local store="$1" tok_name="$2" builder="$3"
        python3 "$builder" "$SECRETS_TMP/cf_pgroups.json" "$tok_name" \
            "$CF_ACCOUNT_ID" "$CF_ZONE_ID" > "$SECRETS_TMP/mint.json" || \
            die "no matchearon los permission groups — revisar nombres arriba"
        _cf_call POST "/accounts/$CF_ACCOUNT_ID/tokens" \
            "$SECRETS_TMP/mint.json" > "$SECRETS_TMP/mint_res.json"
        jq -e '.success == true' "$SECRETS_TMP/mint_res.json" >/dev/null || \
            die "CF rechazó la creación del token $tok_name: $(jq -c '.errors' "$SECRETS_TMP/mint_res.json")"
        jq -r '.result.value' "$SECRETS_TMP/mint_res.json" | tr -d '\n' \
            > "$SECRETS_TMP/$store"
        persist_secret "$store" "$SECRETS_TMP/$store"
        log_ok "token CF acotado acuñado: $tok_name"
        printf '%s' "$SECRETS_TMP/$store"
    }
    CF_API="$(mint_cf_token cf_api_token aegis-v2-tunnel \
              "$AEGIS_ROOT/lib/cf-policy-tunnel.py")"
    CF_DNS="$(mint_cf_token cf_dns_token aegis-v2-dns-cert-manager \
              "$AEGIS_ROOT/lib/cf-policy-dns.py")"
    # #88: el de Access. SEPARADO del de arriba y no un permiso más
    # suyo, porque el job edge-apply de Jenkins recibe el del túnel:
    # si ese token pudiera editar Access, un CI comprometido podría
    # sacarse a sí mismo de detrás de Access.
    CF_ACCESS="$(mint_cf_token cf_access_token aegis-v2-access \
                 "$AEGIS_ROOT/lib/cf-policy-access.py")"
    # la maestra muere ACÁ (efímera de verdad):
    shred -u "$CF_MASTER"
    unset CF_AUTH_EMAIL
    log_ok "maestra CF destruida de tmpfs; quedan SOLO los acotados"
fi

# ═══ 15.2 Material propio (HMACs, deploy keys) — del store ════════
HMAC_ARGO="$(gen_or_restore hmac_argocd gen_hex32)"
HMAC_JENK="$(gen_or_restore hmac_jenkins gen_hex32)"
# corrida #12: los HMAC viven en DOS lados que deben ser
# byte-idénticos (Secret K8s byte-preserving vs GitHub que trimea) —
# un \n final = 400 determinista en toda delivery. Se valida acá
# porque el store RESTAURA material viejo tal cual (pre-fix):
assert_no_newline "$HMAC_ARGO" hmac_argocd
assert_no_newline "$HMAC_JENK" hmac_jenkins

# UNA CLAVE POR CONSUMIDOR, y TODAS de sólo lectura (#83, 2026-08-12).
#
# Hasta acá había una clave de ESCRITURA (dk_app_rw, registrada como
# `aegis-iu-write --allow-write`) que existía para el Image Updater, y
# ArgoCD autenticaba con ELLA. El Image Updater se retiró en #59 y la
# clave se sacó de GitHub a mano en #49 — pero esta fase la seguía
# creando y registrando, así que toda instancia nueva volvía a nacer
# con ella. Medido el 2026-08-12: en GitHub ya no estaba, en el init sí.
#
# La dirección importaba: ArgoCD sólo LEE. Una deploy key con escritura
# en su Secret significa que quien tenga el cluster puede escribir en el
# repo de la app — al revés de lo que uno quiere.
#
# Y son claves SEPARADAS por consumidor a propósito: con una compartida,
# rotar la de Jenkins obliga a tocar ArgoCD, y el radio de cada rotación
# deja de ser el consumidor y pasa a ser todos.
DK_OPS="$(gen_or_restore_keypair dk_ops "argocd-readonly@${PLATFORM_REPO}")"
DK_APP_RO="$(gen_or_restore_keypair dk_app_ro "jenkins-readonly@${APP_REPO}")"
DK_APP_ARGO="$(gen_or_restore_keypair dk_app_argocd_ro "argocd-readonly@${APP_REPO}")"

# ═══ 15.3 registro AUTOMÁTICO de deploy keys (gh, idempotente) ════
# antes: human_step con 3 pegadas en la UI. Ahora: gh repo
# deploy-key add (probado por el operador en la corrida #2).
# Idempotencia por título: si ya está registrada, skip.
add_deploy_key() {   # <repo> <pubfile> <title> [--allow-write]
    local repo="$1" pub="$2" title="$3" write="${4:-}"
    # idempotencia por FINGERPRINT, no por título (corrida #7): si el
    # repo sobrevivió de una corrida anterior (greenfield-vs-estado:
    # el snapshot limpia la VM, no GitHub) su deploy key registrada
    # tiene la PÚBLICA vieja, pero el store regeneró la privada → no
    # matchean → "Permission denied (publickey)". El skip por título
    # NO lo detectaba. Comparamos el blob base64 de la key:
    local ourkey existing
    ourkey="$(awk '{print $2}' "$pub")"
    existing="$(gh repo deploy-key list -R "$GH_OWNER/$repo" \
                  --json title,key --jq \
                  ".[] | select(.title==\"$title\") | .key" 2>/dev/null \
                | awk '{print $2}')"
    if [[ -n "$existing" ]]; then
        if [[ "$existing" == "$ourkey" ]]; then
            log_info "deploy key '$title' ya registrada y COINCIDE con el store — skip"
            return 0
        fi
        log_warn "deploy key '$title' registrada NO coincide con el store (repo previo) — re-registrando"
        local oldid
        oldid="$(gh repo deploy-key list -R "$GH_OWNER/$repo" --json id,title \
                  --jq ".[] | select(.title==\"$title\") | .id")"
        run_cmd gh repo deploy-key delete -R "$GH_OWNER/$repo" "$oldid"
    fi
    local args=(-R "$GH_OWNER/$repo" --title "$title")
    [[ "$write" == "--allow-write" ]] && args+=(--allow-write)
    run_cmd gh repo deploy-key add "$pub" "${args[@]}"
    log_ok "deploy key '$title' registrada en $repo${write:+ (WRITE)}"
}
add_deploy_key "$PLATFORM_REPO" "$DK_OPS.pub"      aegis-argocd-ro
add_deploy_key "$APP_REPO"      "$DK_APP_RO.pub"   aegis-jenkins-ro
add_deploy_key "$APP_REPO"      "$DK_APP_ARGO.pub" aegis-argocd-ro

# verificación real del registro (capability real, no proxy). Una por
# clave: un gate que cubre dos consumidores no dice cuál se rompió.
gate "deploy-key-ops-lee" retry_net 3 bash -c \
  "GIT_SSH_COMMAND='ssh -i $DK_OPS -o IdentitiesOnly=yes' \
   git ls-remote git@github.com:$GH_OWNER/$PLATFORM_REPO.git HEAD >/dev/null"
gate "deploy-key-app-jenkins-lee" retry_net 3 bash -c \
  "GIT_SSH_COMMAND='ssh -i $DK_APP_RO -o IdentitiesOnly=yes' \
   git ls-remote git@github.com:$GH_OWNER/$APP_REPO.git HEAD >/dev/null"
gate "deploy-key-app-argocd-lee" retry_net 3 bash -c \
  "GIT_SSH_COMMAND='ssh -i $DK_APP_ARGO -o IdentitiesOnly=yes' \
   git ls-remote git@github.com:$GH_OWNER/$APP_REPO.git HEAD >/dev/null"

# ═══ 15.4 webhooks AUTOMÁTICOS (gh api --input, secret sin argv) ══
make_repo_webhook() {   # <repo> <url> <hmac-file>
    local repo="$1" url="$2" hmac="$3" hook_id
    # bug corrida #10: "ya existe" NO implica "sincronizado". Un hook
    # sobreviviente de un estado previo firma con un HMAC viejo mientras
    # el receptor valida con el del store (gen_or_restore) → 400
    # permanente en el redeliver. A diferencia del deploy-key de arriba
    # (cuyo blob público SÍ se puede comparar), GitHub NUNCA devuelve
    # config.secret de un hook existente — no hay comparación posible.
    # La única garantía de sincronía: re-escribir el secret SIEMPRE
    # (PATCH idempotente con el HMAC del store).
    # P3 auditoría: el listado con `2>/dev/null | head` trataba un
    # fallo de red como "no hay hook" → POST duplicado en cada
    # retome a medias. retry + fallo EXPLÍCITO del listado:
    local hooks_json
    hooks_json="$(retry_net 3 gh api "repos/$GH_OWNER/$repo/hooks")" || \
        die "no pude LISTAR los hooks de $repo (red/gh) — sin listado no se distingue crear de duplicar"
    hook_id="$(jq -r ".[] | select(.config.url==\"$url\") | .id" \
               <<< "$hooks_json" | head -n1)"
    python3 - "$url" "$hmac" "${hook_id:+patch}" \
        > "$SECRETS_TMP/hook.json" <<'EOF'
import json, sys
url, hmac_file = sys.argv[1], sys.argv[2]
body = {"active": True, "events": ["push"],
        "config": {"url": url, "content_type": "json",
                   "secret": open(hmac_file).read().strip(),
                   "insecure_ssl": "0"}}
if len(sys.argv) < 4 or sys.argv[3] != "patch":
    body["name"] = "web"   # POST lo exige; PATCH no lo acepta
print(json.dumps(body))
EOF
    if [[ -n "$hook_id" ]]; then
        run_cmd bash -c "gh api -X PATCH 'repos/$GH_OWNER/$repo/hooks/$hook_id' \
            --input '$SECRETS_TMP/hook.json' >/dev/null"
        log_ok "webhook $url ya existía en $repo — HMAC re-sincronizado con el store (PATCH, nunca en argv)"
        return 0
    fi
    run_cmd bash -c "gh api -X POST 'repos/$GH_OWNER/$repo/hooks' \
        --input '$SECRETS_TMP/hook.json' >/dev/null"
    log_ok "webhook creado en $repo → $url (HMAC nunca en argv)"
}
# GitHub acepta URLs aún inalcanzables (el edge llega en fase 35;
# los gates de redeliver/e2e cierran el ciclo después):
make_repo_webhook "$PLATFORM_REPO" "https://argocd.$ROOT_DOMAIN/api/webhook" "$HMAC_ARGO"
make_repo_webhook "$APP_REPO"      "https://jenkins.$ROOT_DOMAIN/github-webhook/" "$HMAC_JENK"

# ═══ 15.5 credencial de CI para Jenkins (D11: gh token, no App) ═══
# github-branch-source escanea con una credencial username+password
# (owner + token) — el camino estándar pre-App. El token es el de
# la sesión gh (dogfooding; trade-off y rotación en
# docs/protocols/github-credential.md). Mecánica sin mostrarlo:
gh auth token | tr -d '\n' > "$SECRETS_TMP/gh_token"
gate "gh-token-no-vacio" bash -c "[[ -s '$SECRETS_TMP/gh_token' ]]"
# P2.5 auditoría 2026-07-18: el token de sesión se hornea como
# credencial de CI — si le falta el scope repo, el scan multibranch
# falla DÍAS después sin correlación con esta fase. Gate de scopes
# REALES (el header x-oauth-scopes de la API, no la doc de gh):
gate "gh-token-scope-repo" retry_net 3 bash -c \
  "gh api -i user 2>/dev/null | grep -i '^x-oauth-scopes:' | grep -qw repo"
# (rotación/expiración del token: docs/protocols/github-credential.md)
GH_USER_F="$(materialize gh_user "$GH_OWNER")"

# ═══ 15.6 Cifrado de todo lo producido (KSOPS + tofu) ═════════════
# tokens.enc.yaml = SOLO las keys que el wrapper tofu inyecta (D7/D10).
#
# #88: son DOS desde Access. tofu-apply.sh lee cloudflare.api_token y
# cloudflare.access_token, y muere con "vacío" si falta cualquiera —
# hasta hoy el segundo lo había puesto una mano en #76, así que una
# instancia nueva llegaba a la fase 25 y el apply del borde paraba
# ahí. Los dos salen del mismo lugar y por el mismo mecanismo.
#
# Que los dos vivan en el MISMO archivo no deshace la separación: lo
# que la sostiene es que CI nunca tiene la age key, así que no puede
# abrir este archivo. El job edge-apply recibe su token como
# credencial de Jenkins, y recibe SOLO el del túnel.
python3 - "$CF_API" "$CF_ACCESS" > "$SECRETS_TMP/tokens.yaml" <<'EOF'
import sys, yaml
api = open(sys.argv[1]).read().strip()
access = open(sys.argv[2]).read().strip()
yaml.safe_dump({"cloudflare": {"api_token": {"value": api},
                               "access_token": {"value": access}}},
               sys.stdout, default_flow_style=False)
EOF
# el destino tiene .gitkeep versionado, pero un `mv` a un dir
# inexistente mata la fase en seco (bug de la corrida en Linux
# nativo, 2026-07-25: git no versiona dirs vacíos y la VM se poblaba
# por copia, no por clone). Defensa en profundidad — barata y sin
# efecto si ya existe:
mkdir -p "$TOKENS_DIR"
mv "$SECRETS_TMP/tokens.yaml" "$TOKENS_DIR/tokens.enc.yaml"   # A5: mv 1º
sops_encrypt_repo "$TOKENS_DIR/tokens.enc.yaml"   # --config explícito (patrón A)
gate "tokens-roundtrip" check_sops_roundtrip "$TOKENS_DIR/tokens.enc.yaml"

# el dns token → Secret que los ClusterIssuers referencian:
make_enc_secret cloudflare-dns-token cert-manager \
    "$B/ingress/cert-manager-issuers/secret-cloudflare-dns-token.enc.yaml" \
    "api-token=$CF_DNS"

# ── credenciales de Jenkins para el borde (#48) ───────────────────
# AGREGADAS el 2026-08-05. Los cuatro Secrets existían en el repo desde
# #45 pero NINGUNA fase los producía: se habían creado a mano con sops
# cuando se armó el job del borde, y nunca se cablearon acá.
#
# El modo de fallo es el que este proyecto más persigue: en una
# instancia nueva la age key es otra, el init recifra todo lo que SÍ
# produce, y estos cuatro quedan cifrados con una llave que ya no
# existe. KSOPS no los puede descifrar, la App jenkins-secrets no
# sincroniza nunca, y el mensaje habla de MAC y de sops — no de que
# faltó una línea acá.
#
# Los cuatro valores ya están a mano en esta fase: $CF_API es el mismo
# token que se acaba de acuñar, y los otros tres salen de la conf. No
# hay nada nuevo que pedirle al operador.
#
# Ojo con qué es cada uno. El TOKEN es una credencial —el job del borde
# solo LEE la zona (§4 de docs/protocols/edge.md)— y los otros tres son
# identificadores, no secretos. Van cifrados igual porque el mecanismo
# es uno solo: una excepción "esto no hace falta cifrarlo" es una
# excepción que después hay que recordar.
CF_JENKINS_DESC="Token de API de Cloudflare. Lo usa el job edge-chequeo (solo LEE la zona) y el operador via tofu-apply.sh. La age key NO entra a CI."
make_enc_secret cloudflare-api-token jenkins-system \
    "$B/platform/jenkins-secrets/secret-cloudflare-api-token.enc.yaml" \
    --label jenkins.io/credentials-type=secretText \
    --annotation "jenkins.io/credentials-description=$CF_JENKINS_DESC" \
    "text=$CF_API"
make_enc_secret cloudflare-account-id jenkins-system \
    "$B/platform/jenkins-secrets/secret-cloudflare-account-id.enc.yaml" \
    --label jenkins.io/credentials-type=secretText \
    --annotation "jenkins.io/credentials-description=Account ID de Cloudflare (identificador, no secreto)." \
    "text=$(materialize cf_account_id "$CF_ACCOUNT_ID")"
make_enc_secret cloudflare-zone-id jenkins-system \
    "$B/platform/jenkins-secrets/secret-cloudflare-zone-id.enc.yaml" \
    --label jenkins.io/credentials-type=secretText \
    --annotation "jenkins.io/credentials-description=Zone ID de Cloudflare (identificador, no secreto)." \
    "text=$(materialize cf_zone_id "$CF_ZONE_ID")"
make_enc_secret root-domain jenkins-system \
    "$B/platform/jenkins-secrets/secret-root-domain.enc.yaml" \
    --label jenkins.io/credentials-type=secretText \
    --annotation "jenkins.io/credentials-description=Dominio raiz de la instancia (identificador, no secreto)." \
    "text=$(materialize root_domain "$ROOT_DOMAIN")"

make_enc_secret github-webhook argocd \
    "$B/platform/argocd-secrets/secret-github-webhook.enc.yaml" \
    --label app.kubernetes.io/part-of=argocd \
    "token=$HMAC_ARGO"

APP_URL="$(materialize app_repo_url "git@github.com:$GH_OWNER/$APP_REPO.git")"
APP_NAME="$(materialize app_repo_name "$APP_REPO")"
REPO_TYPE="$(materialize repo_type git)"
make_enc_secret hello-aegis-repo argocd \
    "$B/platform/argocd-secrets/secret-hello-aegis-repo.enc.yaml" \
    --label argocd.argoproj.io/secret-type=repository \
    "sshPrivateKey=$DK_APP_ARGO" \
    "url=$APP_URL" "name=$APP_NAME" "type=$REPO_TYPE"

GIT_USER="$(materialize git_user git)"
make_enc_secret hello-aegis-repo jenkins-system \
    "$B/platform/jenkins-secrets/secret-hello-aegis-repo.enc.yaml" \
    --label jenkins.io/credentials-type=basicSSHUserPrivateKey \
    --annotation "jenkins.io/credentials-description=deploy key RO checkout ${APP_REPO}" \
    "privateKey=$DK_APP_RO" "username=$GIT_USER"

# checkout del repo de PLATAFORMA para el job ci-images (bug cazado
# en sesión 6: el job clonaba plataforma con la key de la APP):
make_enc_secret ops-stack-repo-ro jenkins-system \
    "$B/platform/jenkins-secrets/secret-ops-stack-repo-ro.enc.yaml" \
    --label jenkins.io/credentials-type=basicSSHUserPrivateKey \
    --annotation "jenkins.io/credentials-description=deploy key RO checkout ${PLATFORM_REPO} (job ci-images)" \
    "privateKey=$DK_OPS" "username=$GIT_USER"

# la credencial de CI (username+token — reemplaza a la GitHub App):
make_enc_secret github-token jenkins-system \
    "$B/platform/jenkins-secrets/secret-github-token.enc.yaml" \
    --label jenkins.io/credentials-type=usernamePassword \
    --annotation "jenkins.io/credentials-description=gh session token para scan multibranch (D11)" \
    "username=$GH_USER_F" "password=$SECRETS_TMP/gh_token"

make_enc_secret github-webhook-hmac jenkins-system \
    "$B/platform/jenkins-secrets/secret-github-webhook-hmac.enc.yaml" \
    --label jenkins.io/credentials-type=secretText \
    --annotation "jenkins.io/credentials-description=HMAC webhook GitHub→Jenkins" \
    "text=$HMAC_JENK"

OPS_URL="$(materialize ops_url "git@github.com:$GH_OWNER/$PLATFORM_REPO.git")"
OPS_NAME="$(materialize ops_name "$PLATFORM_REPO")"
make_enc_secret ops-stack-repo argocd \
    "$B/platform/argocd-secrets/secret-ops-stack-repo.enc.yaml" \
    --label argocd.argoproj.io/secret-type=repository \
    "sshPrivateKey=$DK_OPS" "url=$OPS_URL" \
    "name=$OPS_NAME" "type=$REPO_TYPE"

log_ok "Terceros AUTOMÁTICOS completos: tokens CF acuñados por API, \
3 deploy keys registradas por gh, 2 webhooks creados, credencial CI \
del gh token — cero navegador, cero archivos movidos a mano"
