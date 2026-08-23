#!/usr/bin/env bash
# FASE 12 — repos de trabajo: el init los CREA y SIEMBRA (D10).
# AISLAMIENTO: los repos del v2 son DESECHABLES y propios
# (ops-stack-v2 / hello-aegis-v2 por default) — el init les escribe
# commits, tags, settings y webhooks; JAMÁS deben ser los repos
# reales del v1. El operador no crea repos a mano (misión: el init
# pregunta y hace).
#
# También corrige de raíz el bug de secuencia v2: la fase 15
# registra deploy keys y gatea ls-remote contra repos que antes
# recién creaba la 25 — ahora existen desde acá.
#
# Idempotencia: los repos del init llevan el topic
# `aegis-v2-disposable` (marcador). Re-corrida: existe+marcado →
# reutiliza; existe SIN marcar → ROJO (podría ser un repo real).
#
# Credencial: la sesión gh ya autenticada (gate de fase 00) — no
# hay PAT propio del init (D10 eliminó el PAT del flujo: un token
# emitido para un consumidor que ya no existe era superficie
# gratis). Git pushes del host van por https con el credential
# helper de gh; las deploy keys SSH quedan para los consumidores
# in-cluster (fase 15).
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"

MARK_TOPIC="aegis-v2-disposable"

# ── 12.0 git en el host: identidad + credencial + known_hosts ──────
git config --global user.name  >/dev/null 2>&1 || \
    run_cmd git config --global user.name "aegis-init"
git config --global user.email >/dev/null 2>&1 || \
    run_cmd git config --global user.email "aegis-init@${ROOT_DOMAIN}"
run_cmd gh auth setup-git    # helper https (idempotente)

# known_hosts de github.com desde los pins T1 del values de jenkins
# (FUENTE ÚNICA de host keys, verificada contra /meta en fase 00) —
# jamás TOFU (nada de accept-first-connection):
KH="$HOME/.ssh/known_hosts"
run_cmd mkdir -p "$HOME/.ssh"; run_cmd chmod 700 "$HOME/.ssh"
grep -q 'github.com ssh-ed25519' "$KH" 2>/dev/null || run_cmd bash -c \
  "grep -Eo 'github\.com (ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa) [A-Za-z0-9+/=]+' \
     '$PLATFORM_DIR/k8s/base/platform/jenkins/values.yaml' >> '$KH'"
gate "known-hosts-github" grep -q 'github.com ssh-ed25519' "$KH"

# ── 12.1 crear/reusar cada repo (idempotente con marcador) ─────────
ensure_repo() {
    local repo="$1" desc="$2"
    if gh repo view "$GH_OWNER/$repo" >/dev/null 2>&1; then
        # existe: ¿es NUESTRO (marcado) o un repo real? La distinción
        # es el corazón del aislamiento:
        if gh api "repos/$GH_OWNER/$repo/topics" --jq '.names[]' \
             2>/dev/null | grep -qx "$MARK_TOPIC"; then
            log_info "repo $repo ya existe con marcador $MARK_TOPIC — reutilizo"
        else
            log_warn "repo $GH_OWNER/$repo EXISTE y NO tiene el marcador"
            # P0.1 auditoría: en --non-interactive esto NO se
            # auto-confirma — el seed hace push --force y marcar un
            # repo ajeno como desechable lo PISARÍA. Desatendido no
            # decide sobre lo que no está marcado como nuestro:
            ni_mode && die "repo $GH_OWNER/$repo existe SIN marcador $MARK_TOPIC y no hay operador para decidir — elegí otro nombre en el conf o marcá el repo a mano si de verdad es desechable"
            gate_red "usar $GH_OWNER/$repo como repo DESECHABLE del v2 — si es un repo real (v1), ABORTÁ y elegí otro nombre con --configure"
            run_cmd gh api -X PUT "repos/$GH_OWNER/$repo/topics" \
                -f "names[]=$MARK_TOPIC"
        fi
    else
        run_cmd gh repo create "$GH_OWNER/$repo" --private \
            --description "$desc"
        run_cmd gh api -X PUT "repos/$GH_OWNER/$repo/topics" \
            -f "names[]=$MARK_TOPIC"
        log_ok "repo $repo creado (privado, marcado $MARK_TOPIC)"
    fi
    # settings B4 + squash (antes tofu github-repos — D10: gh api
    # idempotente, sin state, sin PAT):
    run_cmd gh api -X PATCH "repos/$GH_OWNER/$repo" \
        -F delete_branch_on_merge=false \
        -F allow_squash_merge=true \
        -f squash_merge_commit_title=COMMIT_OR_PR_TITLE \
        -f squash_merge_commit_message=COMMIT_MESSAGES >/dev/null
    gate "b4-false-$repo" bash -c \
      "gh api repos/$GH_OWNER/$repo --jq .delete_branch_on_merge | grep -qx false"
}
ensure_repo "$PLATFORM_REPO" "aegis v2 — plataforma (repo de prueba DESECHABLE)"
ensure_repo "$APP_REPO"      "aegis v2 — canary (repo de prueba DESECHABLE)"

# ── 12.2 sembrar PLATFORM_REPO con platform/ del artefacto ─────────
# platform/ ES el working tree (ya renderizado por la fase 10):
if [[ ! -d "$PLATFORM_DIR/.git" ]]; then
    run_cmd git -C "$PLATFORM_DIR" init -b main
fi
if git -C "$PLATFORM_DIR" remote get-url origin >/dev/null 2>&1; then
    run_cmd git -C "$PLATFORM_DIR" remote set-url origin \
        "https://github.com/$GH_OWNER/$PLATFORM_REPO.git"
else
    run_cmd git -C "$PLATFORM_DIR" remote add origin \
        "https://github.com/$GH_OWNER/$PLATFORM_REPO.git"
fi
# clase F auditoría: commit condicionado a staged real, sin || que
# trague un fallo de commit legítimo (hook, identidad, index.lock):
git_commit_if_changes "$PLATFORM_DIR" \
    "feat(bootstrap): plataforma v2 inicial (seed de aegis-init)"
# push --force DELIBERADO (corrida #4): en una corrida desde snapshot
# el .git local es nuevo y el remoto tiene la historia de la corrida
# anterior → "fetch first" con mensaje engañoso de red. El remoto es
# NUESTRO y desechable POR CONSTRUCCIÓN (ensure_repo verificó el
# marcador o frenó en ROJO arriba); el working tree local es la
# fuente de verdad del seed. Jamás aplicar este patrón a un repo
# real:
run_cmd retry_net 3 git -C "$PLATFORM_DIR" push -u --force origin main || \
    die "push de plataforma falló — revisar red/permisos gh y --from 12"
gate "platform-repo-sembrado" retry_net 3 bash -c \
    "git ls-remote https://github.com/$GH_OWNER/$PLATFORM_REPO.git HEAD | grep -q ."

# ── 12.3 sembrar APP_REPO con el canary ────────────────────────────
# H6 corrida #15: el "no re-siembro si tiene contenido" dejó VIVO el
# .argocd-source-hello-aegis.yaml del write-back de la corrida
# ANTERIOR — ArgoCD lo trata como override de parámetros y pisa el
# newTag → el canary pidió un tag inexistente (ImagePullBackOff) y
# la alineación de la 70 no tuvo efecto (miraba el kustomization, no
# la fuente efectiva). LA familia catalogada (residuos de corridas
# previas) mordió por el archivo que el seed NO contiene: escribir
# encima no garantiza estado-igual-al-seed. Fix de la CLASE: si la
# fase 12 corre, el canary se siembra SIEMPRE con historia HUÉRFANA
# + push --force (mismo contrato que el platform seed: repos
# marcados desechables POR CONSTRUCCIÓN — ensure_repo verificó el
# marcador o frenó arriba). Correr la 12 ES pedir greenfield del
# canary; los builds/write-backs de la corrida en curso viven en
# fases posteriores, que el marker de la 12 protege (--from 12
# explícito = re-seed deliberado, documentado acá):
{
    SEED_TMP="$(mktemp -d)"
    run_cmd cp -r "$AEGIS_ROOT/semilla/canario/." "$SEED_TMP/"
    # el Jenkinsfile del canary se INSTANCIA del template de
    # plataforma (fuente única — no hay segunda copia que driftee).
    # IMAGE queda 'hello-aegis' fijo: es la identidad del canary
    # (la App, el CR del IU y el Deployment la usan); el nombre del
    # REPO es libre:
    run_cmd bash -c "sed \"s/CHANGEME-app/hello-aegis/\" \
      '$PLATFORM_DIR/docs/protocols/templates/Jenkinsfile.app' \
      > '$SEED_TMP/Jenkinsfile'"
    # CR-5 corrida #14: el seed NO pasa por render_platform_placeholders
    # (eso es de platform/) — el dominio del IngressRoute del canary se
    # renderiza ACÁ, al sembrar. Gate del resultado: un placeholder vivo
    # en el app repo sería un Host literal 'aegis.__ROOT_DOMAIN__':
    run_cmd bash -c "grep -rl '__ROOT_DOMAIN__' '$SEED_TMP' \
      | xargs -r sed -i 's/__ROOT_DOMAIN__/$ROOT_DOMAIN/g'"
    gate "seed-sin-placeholders" bash -c \
      "! grep -rq '__ROOT_DOMAIN__' '$SEED_TMP'"
    run_cmd git -C "$SEED_TMP" init -b main
    run_cmd git -C "$SEED_TMP" add -A
    run_cmd git -C "$SEED_TMP" commit -m \
        "feat: canary hello-aegis v2 (seed de aegis-init)" --no-verify
    run_cmd git -C "$SEED_TMP" remote add origin \
        "https://github.com/$GH_OWNER/$APP_REPO.git"
    # --force: historia huérfana pisa la del run anterior (H6). El
    # sha local queda para el gate de estado-igual-al-seed:
    SEED_SHA="$(git -C "$SEED_TMP" rev-parse HEAD)"
    run_cmd retry_net 3 git -C "$SEED_TMP" push -u --force origin main || \
        die "push del canary falló — revisar red/permisos gh y --from 12"
    rm -rf "$SEED_TMP"
}
# el gate valida el RESULTADO, no la intención (familia H6): el HEAD
# remoto debe ser EXACTAMENTE el commit del seed — cualquier residuo
# (.argocd-source-*, tags viejos en el tree) implicaría otro sha:
gate "app-repo-estado-igual-al-seed" retry_net 3 bash -c \
    "git ls-remote https://github.com/$GH_OWNER/$APP_REPO.git refs/heads/main \
     | grep -q '^$SEED_SHA'"

log_ok "Repos de trabajo listos y marcados como desechables: \
$GH_OWNER/$PLATFORM_REPO (plataforma) + $GH_OWNER/$APP_REPO (canary)"
