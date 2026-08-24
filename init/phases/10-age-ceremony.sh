#!/usr/bin/env bash
# FASE 10 — ceremonia de la clave age (la raíz de confianza).
# Generaliza rotate-age-key.md §A: generación + 3 resguardos +
# VALIDACIÓN POR ROUNDTRIP REAL (no confirmación verbal) + workspace
# operativo (path custom ADR-0003 + direnv + .envrc).
# ROJO por diseño: es la única fase que MUESTRA un secreto (una vez,
# para resguardo del operador — principio secreto-al-operador).
set -euo pipefail

AGE_OPS_PATH="$HOME/.config/sops/age/aegis.key"   # ADR-0003: JAMÁS keys.txt
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"

# ── re-bootstrap corto-circuito: si ya hay key operativa, validar y
#    salir (idempotencia; el greenfield puro sigue de largo) ────────
if [[ -f "$AGE_OPS_PATH" ]]; then
    log_warn "Ya existe $AGE_OPS_PATH — modo 'key existente'"
    export SOPS_AGE_KEY_FILE="$AGE_OPS_PATH"
    gate "age-existente-operativa" check_age_key_operational
    # P3 auditoría 2026-07-18: este atajo SALTABA el render — un
    # re-run tras muerte parcial (key instalada, render no corrido)
    # dejaba __GH_OWNER__/__ROOT_DOMAIN__ VIVOS para las fases 12+.
    # El atajo exime lo IRREPETIBLE (generar/mostrar la key); la
    # parte idempotente corre SIEMPRE:
    AGE_PUBLIC="$(age-keygen -y "$AGE_OPS_PATH")"
    gate "age-public-derivada" bash -c "[[ '$AGE_PUBLIC' == age1* ]]"
    echo "$AGE_PUBLIC" > "$AEGIS_HOME/.age-public"
    if [[ -f "$PLATFORM_DIR/.sops.yaml.tpl" && ! -f "$PLATFORM_DIR/.sops.yaml" ]]; then
        run_cmd bash -c "sed 's/__AGE_PUBLIC__/$AGE_PUBLIC/' \
            '$PLATFORM_DIR/.sops.yaml.tpl' > '$PLATFORM_DIR/.sops.yaml'"
        log_ok ".sops.yaml regenerado (faltaba — muerte parcial previa)"
    fi
    render_platform_placeholders   # idempotente: sin vivos es no-op
    log_ok "age key existente validada; fase 10 completa (sin generar; render verificado)"
    return 0 2>/dev/null || exit 0
fi

# ── A6/A5 aplican después; acá: generar + ceremonia ────────────────
secrets_workdir
AGE_TMP="$(gen_age_key)"     # stdout = SOLO el path (H4)
gate "age-key-generada" test -s "$AGE_TMP"

# la pública (T1) se deriva DEL ARCHIVO con la herramienta oficial
# — sobrevive cualquier subshell por construcción (H4: setearla
# dentro de gen_age_key moría en el $()):
AGE_PUBLIC="$(age-keygen -y "$AGE_TMP")"
gate "age-public-derivada" bash -c "[[ '$AGE_PUBLIC' == age1* ]]"
log_info "pública: $AGE_PUBLIC"

# guardar la pública para el resto del init (T1, sin secreto):
echo "$AGE_PUBLIC" > "$AEGIS_HOME/.age-public"

# ── ceremonia: mostrar UNA vez + resguardos + roundtrip ────────────
ceremony_backup "age key (IRREEMPLAZABLE — pierde esto y se pierde \
TODO lo cifrado)" "$AGE_TMP" validate_age_backup \
    "pendrive offline 'aegis-offline' + /aegis/secrets-offline/"

# ── instalar la copia operativa (600) ──────────────────────────────
run_cmd install -D -m 600 "$AGE_TMP" "$AGE_OPS_PATH"
export SOPS_AGE_KEY_FILE="$AGE_OPS_PATH"
gate "age-operativa" check_age_key_operational

# ── workspace: .envrc + direnv allow (A2/A3) ───────────────────────
# El init NO depende de direnv (exporta explícito — A2); el .envrc es
# para el trabajo interactivo posterior del operador.
WORKSPACE="${AEGIS_WORKSPACE:-$HOME/aegis}"
if [[ -d "$WORKSPACE" ]]; then
    if [[ ! -f "$WORKSPACE/.envrc" ]]; then
        run_cmd bash -c "printf 'export SOPS_AGE_KEY_FILE=%q\n' \
            '$AGE_OPS_PATH' > '$WORKSPACE/.envrc'"
        run_cmd direnv allow "$WORKSPACE"
        log_ok ".envrc creado + direnv allow en $WORKSPACE"
    fi
fi

# ── SEMBRAR platform/ DESDE LA SEED ─────────────────────────────
#
# Hasta el 2026-08-05 no hacía falta: `platform/` era a la vez la
# semilla (trackeada por el repo del producto) y el directorio de
# trabajo de la instancia. Dos repos sobre una misma carpeta.
#
# Eso tenía dos consecuencias, las dos medidas:
#   - La semilla se congeló. La instancia viva avanzó una semana y
#     nada de eso volvió, porque devolverlo exige DES-renderizar los
#     placeholders que esta misma fase resuelve más abajo.
#   - Trabajar la semilla era peligroso: un `git checkout -- platform/`
#     distraído pisaba los archivos de la instancia CORRIENDO.
#
# Ahora la semilla vive en seed/platform/ (sin renderizar) y se
# COPIA acá. El render de abajo sigue operando sobre platform/, o sea
# sobre la copia, y la semilla nunca queda con valores de una
# instancia adentro.
#
# LA GUARDA ES LO IMPORTANTE: si platform/ ya tiene .git, esto NO es
# un arranque virgen — es una instancia con historia propia, y su
# working tree es la verdad. Copiar la semilla encima la destruiría.
SEMILLA_PLATAFORMA="$AEGIS_ROOT/seed/platform"
[[ -d "$SEMILLA_PLATAFORMA" ]] || die "falta seed/platform/ — el artefacto está incompleto"
if [[ -d "$PLATFORM_DIR/.git" ]]; then
    log_info "platform/ ya es una instancia (tiene .git): NO se siembra desde la semilla"
else
    run_cmd mkdir -p "$PLATFORM_DIR"
    # -a preserva modos (bin/ tiene ejecutables); el `.` copia también
    # los ocultos, que incluyen .sops.yaml.tpl y .gitignore.
    run_cmd cp -a "$SEMILLA_PLATAFORMA/." "$PLATFORM_DIR/"
    log_ok "platform/ sembrado desde seed/platform/ ($(find "$SEMILLA_PLATAFORMA" -type f | wc -l) archivos)"
fi

# ── .sops.yaml del repo de plataforma: recipient = la pública ──────
# (en greenfield el repo v2 se inicializa con ESTA pública; el
#  placeholder se reemplaza acá — ver seed/platform/.sops.yaml.tpl)
SOPS_TPL="$PLATFORM_DIR/.sops.yaml.tpl"
if [[ -f "$SOPS_TPL" ]]; then
    run_cmd bash -c "sed 's/__AGE_PUBLIC__/$AGE_PUBLIC/' '$SOPS_TPL' \
        > '$PLATFORM_DIR/.sops.yaml'"
    log_ok ".sops.yaml del repo generado con el recipient nuevo"
fi

# ── render ÚNICO de placeholders de clase-config (dueño: esta fase) ─
# Todos los __GH_OWNER__/__ROOT_DOMAIN__/etc. de platform/ se
# resuelven acá, ANTES de que ninguna fase consuma un manifest.
# (los de clase-generado quedan: __COSIGN_PUB__/__AEGIS_CA_PEM__
#  son de la fase 80 — ver render_platform_placeholders en common.sh)
render_platform_placeholders
log_ok "platform/ renderizado desde aegis-init.conf (un solo paso)"

log_ok "Ceremonia age completa: 3 resguardos validados, copia \
operativa 600, workspace configurado"
