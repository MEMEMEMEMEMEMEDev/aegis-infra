#!/usr/bin/env bash
# PHASE 10 — the age key ceremony (the root of trust).
# Generalizes rotate-age-key.md §A: generation + 3 backups + REAL
# ROUNDTRIP VALIDATION (not a verbal confirmation) + an operational
# workspace (custom path ADR-0003 + direnv + .envrc).
# RED by design: it is the only phase that SHOWS a secret (once, for
# the operator's safekeeping — the secret-to-the-operator principle).
set -euo pipefail

AGE_OPS_PATH="$HOME/.config/sops/age/aegis.key"   # ADR-0003: NEVER keys.txt
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"

# ── re-bootstrap short-circuit: if there is already an operational
#    key, validate and leave (idempotence; pure greenfield goes
#    straight through) ──────────────────────────────────────────────
if [[ -f "$AGE_OPS_PATH" ]]; then
    log_warn "$AGE_OPS_PATH already exists — 'existing key' mode"
    export SOPS_AGE_KEY_FILE="$AGE_OPS_PATH"
    gate "age-existente-operativa" check_age_key_operational
    # P3 audit 2026-07-18: this shortcut SKIPPED the render — a re-run
    # after a partial death (key installed, render not run) left
    # __GH_OWNER__/__ROOT_DOMAIN__ ALIVE for phases 12+. The shortcut
    # exempts what is UNREPEATABLE (generating/showing the key); the
    # idempotent part runs ALWAYS:
    AGE_PUBLIC="$(age-keygen -y "$AGE_OPS_PATH")"
    gate "age-public-derivada" bash -c "[[ '$AGE_PUBLIC' == age1* ]]"
    echo "$AGE_PUBLIC" > "$AEGIS_HOME/.age-public"
    if [[ -f "$PLATFORM_DIR/.sops.yaml.tpl" && ! -f "$PLATFORM_DIR/.sops.yaml" ]]; then
        run_cmd bash -c "sed 's/__AGE_PUBLIC__/$AGE_PUBLIC/' \
            '$PLATFORM_DIR/.sops.yaml.tpl' > '$PLATFORM_DIR/.sops.yaml'"
        log_ok ".sops.yaml regenerated (it was missing — a previous partial death)"
    fi
    render_platform_placeholders   # idempotent: with none alive it is a no-op
    log_ok "existing age key validated; phase 10 complete (nothing generated; render verified)"
    return 0 2>/dev/null || exit 0
fi

# ── A6/A5 apply later; here: generate + ceremony ──────────────────
secrets_workdir
AGE_TMP="$(gen_age_key)"     # stdout = ONLY the path (H4)
gate "age-key-generada" test -s "$AGE_TMP"

# the public part (T1) is derived FROM THE FILE with the official
# tool — it survives any subshell by construction (H4: setting it
# inside gen_age_key died in the $()):
AGE_PUBLIC="$(age-keygen -y "$AGE_TMP")"
gate "age-public-derivada" bash -c "[[ '$AGE_PUBLIC' == age1* ]]"
log_info "public: $AGE_PUBLIC"

# store the public part for the rest of the init (T1, no secret):
echo "$AGE_PUBLIC" > "$AEGIS_HOME/.age-public"

# ── ceremony: show ONCE + backups + roundtrip ─────────────────────
ceremony_backup "age key (IRREPLACEABLE — lose this and EVERYTHING \
encrypted is lost)" "$AGE_TMP" validate_age_backup \
    "offline USB stick 'aegis-offline' + /aegis/secrets-offline/"

# ── install the operational copy (600) ────────────────────────────
run_cmd install -D -m 600 "$AGE_TMP" "$AGE_OPS_PATH"
export SOPS_AGE_KEY_FILE="$AGE_OPS_PATH"
gate "age-operativa" check_age_key_operational

# ── workspace: .envrc + direnv allow (A2/A3) ──────────────────────
# The init does NOT depend on direnv (it exports explicitly — A2); the
# .envrc is for the operator's later interactive work.
WORKSPACE="${AEGIS_WORKSPACE:-$HOME/aegis}"
if [[ -d "$WORKSPACE" ]]; then
    if [[ ! -f "$WORKSPACE/.envrc" ]]; then
        run_cmd bash -c "printf 'export SOPS_AGE_KEY_FILE=%q\n' \
            '$AGE_OPS_PATH' > '$WORKSPACE/.envrc'"
        run_cmd direnv allow "$WORKSPACE"
        log_ok ".envrc created + direnv allow in $WORKSPACE"
    fi
fi

# ── SEED platform/ FROM THE SEED ────────────────────────────────
#
# Until 2026-08-05 this was not needed: `platform/` was at once the
# seed (tracked by the product's repo) and the instance's working
# directory. Two repos over a single folder.
#
# That had two consequences, both measured:
#   - The seed froze. The live instance moved on for a week and none
#     of it came back, because bringing it back requires UN-rendering
#     the placeholders this very phase resolves further down.
#   - Working on the seed was dangerous: a distracted
#     `git checkout -- platform/` trampled the files of the RUNNING
#     instance.
#
# Now the seed lives in seed/platform/ (unrendered) and is COPIED
# here. The render below still operates on platform/, that is, on the
# copy, and the seed is never left with one instance's values inside.
#
# THE GUARD IS THE IMPORTANT PART: if platform/ already has .git, this
# is NOT a virgin start — it is an instance with a history of its own,
# and its working tree is the truth. Copying the seed on top would
# destroy it.
PLATFORM_SEED="$AEGIS_ROOT/seed/platform"
[[ -d "$PLATFORM_SEED" ]] || die "seed/platform/ is missing — the artifact is incomplete"
if [[ -d "$PLATFORM_DIR/.git" ]]; then
    log_info "platform/ is already an instance (it has .git): NOT seeding from the seed"
else
    run_cmd mkdir -p "$PLATFORM_DIR"
    # -a preserves modes (bin/ has executables); the `.` also copies
    # the hidden files, which include .sops.yaml.tpl and .gitignore.
    run_cmd cp -a "$PLATFORM_SEED/." "$PLATFORM_DIR/"
    log_ok "platform/ seeded from seed/platform/ ($(find "$PLATFORM_SEED" -type f | wc -l) files)"
fi

# ── the platform repo's .sops.yaml: recipient = the public key ─────
# (in greenfield the v2 repo is initialized with THIS public key; the
#  placeholder is replaced here — see seed/platform/.sops.yaml.tpl)
SOPS_TPL="$PLATFORM_DIR/.sops.yaml.tpl"
if [[ -f "$SOPS_TPL" ]]; then
    run_cmd bash -c "sed 's/__AGE_PUBLIC__/$AGE_PUBLIC/' '$SOPS_TPL' \
        > '$PLATFORM_DIR/.sops.yaml'"
    log_ok "the repo's .sops.yaml generated with the new recipient"
fi

# ── SINGLE render of config-class placeholders (owner: this phase) ─
# Every __GH_OWNER__/__ROOT_DOMAIN__/etc. in platform/ is resolved
# here, BEFORE any phase consumes a manifest.
# (the generated-class ones stay: __COSIGN_PUB__/__AEGIS_CA_PEM__
#  belong to phase 80 — see render_platform_placeholders in common.sh)
render_platform_placeholders
log_ok "platform/ rendered from aegis-init.conf (a single step)"

log_ok "age ceremony complete: 3 backups validated, operational copy \
600, workspace configured"
