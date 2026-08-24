#!/usr/bin/env bash
# aegis-init lib/secrets.sh — THE SECRETS MECHANISM. INERT by
# design: it defines HOW material gets generated/encrypted/backed up
# when the init runs; this artifact generates no real material.
#
# Baked-in principles (each one born of a real pothole; refs = doc 26):
#  - random + an encrypted backup in the store (D11) as the MAIN
#    path — the operator only backs up THE AGE KEY; manual entry =
#    an explicit exception (verdict 20.2).
#  - the agent/init handles MECHANICS without seeing values: no
#    secrets in argv (/proc/PID/cmdline — A27), none in logs,
#    shape-checks of LENGTH only.
#  - byte-preserving ALWAYS: kubectl --from-file, never stringData by
#    hand (A6: 1 byte of folding broke a real HMAC).
#  - SOPS: mv into the repo FIRST, encrypt AFTERWARDS (A5:
#    path_regex) + a validation roundtrip ALWAYS.
#  - shared credentials: ONE origin, derivation in the SAME process,
#    an atomic commit (A27: a real 6-day mismatch).
#  - irreplaceables (age, cosign, write key): a ceremony whose backup
#    is validated by a REAL ROUNDTRIP, not by a verbal confirmation
#    (verdict 20.3; pattern rotate-age-key.md §A).
#  - transient material ONLY in tmpfs (/dev/shm) with shred on exit.

set -euo pipefail

# ── ephemeral work area ─────────────────────────────────────────────
# secrets_workdir: per-phase tmpfs, chmod 700, destroyed with shred in
# the EXIT trap. ALL cleartext material lives ONLY here and ONLY for
# the duration of the phase.
secrets_workdir() {
    umask 077   # W-03: every file the phase creates is born 600/700
                # (store, tmpfs, .enc) — closes "material is born 0664"
    SECRETS_TMP="$(mktemp -d /dev/shm/aegis-init.XXXXXX)"
    chmod 700 "$SECRETS_TMP"
    # clean up ALWAYS, whatever happens; separate steps, no && (rule)
    # W-03: INT/TERM as well as EXIT — Ctrl-C fires the tmpfs shred
    # (before, only EXIT: a Ctrl-C left cleartext material in /dev/shm):
    trap 'secrets_cleanup; exit 130' INT TERM
    trap 'secrets_cleanup' EXIT
}
secrets_cleanup() {
    [[ -n "${SECRETS_TMP:-}" && -d "$SECRETS_TMP" ]] || return 0
    find "$SECRETS_TMP" -type f -exec shred -u {} \;
    # rm -rf, NOT rmdir (run #9): registry_creds creates the docker/
    # subdir inside SECRETS_TMP; shred destroys the FILES but the empty
    # subdir remains → rmdir of the parent fails → the whole phase is
    # marked FAILED with all its work done. The sensitive material has
    # already been destroyed by shred; rm -rf only clears away the
    # skeleton of dirs:
    rm -rf "$SECRETS_TMP"
}

# ── SOPS environment RE-DERIVABLE AT THE POINT OF USE ───────────────
# Bug 5 of validation #3: phase_env re-derives before every phase, but
# the environment was lost all the same in some subshell of the --from
# path. Fix of the CLASS: every function in this lib that invokes sops
# re-derives it itself from disk (derive, do not carry — the same
# principle, applied one level further down, where there are no holes
# left).
sops_env() {
    local k="$HOME/.config/sops/age/aegis.key"
    if [[ ! -f "${SOPS_AGE_KEY_FILE:-/nonexistent}" && -f "$k" ]]; then
        export SOPS_AGE_KEY_FILE="$k"
    fi
    if [[ -z "${AGE_PUBLIC:-}" && -f "$AEGIS_HOME/.age-public" ]]; then
        AGE_PUBLIC="$(cat "$AEGIS_HOME/.age-public")"
        export AGE_PUBLIC
    fi
    return 0
}

# ── encryption INTO THE REPO with an EXPLICIT config ────────────────
# Pattern A of validation #3: sops without --config looks for a
# .sops.yaml in the CWD — and the init runs from init/, not from
# platform/ → "no matching creation rules" on EVERY encryption into
# the repo. The store's fix (persist_secret) had not been propagated.
# Fix of the CLASS: a single point of encryption-into-the-repo, with
# platform/'s .sops.yaml made explicit (path_regex resolves relative
# to the config, not to the CWD). verify-static check 16 hunts down
# any future sops -e that skips it.
sops_encrypt_repo() {   # <file under platform/>
    sops_env
    sops --config "$PLATFORM_DIR/.sops.yaml" -e --in-place "$1"
}

# ── store of ENCRYPTED persistence across runs ──────────────────────
# Bug 6 of run #2: resuming with --from REGENERATED secrets that were
# already registered with third parties (orphaned deploy keys, new
# HMACs that did not match the webhooks) → an infernal cycle of
# redoing everything. Root fix: every GENERATED secret is persisted
# encrypted with the age key (the same level of protection as the
# repo's .enc.yaml) in .state-secrets/, and the phases RESTORE before
# generating.
# Model: the age key decrypts everything → the ONLY irreducible the
# operator backs up is the age key; the rest is recoverable.
STATE_SECRETS="${AEGIS_HOME}/.state-secrets"

persist_secret() {   # persist_secret <name> <file-in-tmpfs>
    local name="$1" src="$2"
    sops_env
    : "${AGE_PUBLIC:?persist_secret needs AGE_PUBLIC (phase 10+)}"
    mkdir -p "$STATE_SECRETS"; chmod 700 "$STATE_SECRETS"
    # the store's OWN explicit config: without it, sops looks for a
    # .sops.yaml by path and "no matching creation rules" left an
    # EMPTY .enc because of the redirection (a bug caught by session
    # 6's harness — the failure was silent):
    printf 'creation_rules:\n  - age: %s\n' "$AGE_PUBLIC" \
        > "$STATE_SECRETS/.sops.yaml"
    # P2.1 audit 2026-07-18: the `> $name.enc` redirection TRUNCATES
    # the previous ciphertext BEFORE sops runs — if sops fails on a
    # re-run, the .enc is left at 0 bytes and material already
    # synchronised with third parties is LOST (deploy keys, HMACs).
    # Write to .tmp + roundtrip over the .tmp + atomic mv: the good
    # .enc survives any intermediate failure:
    sops --config "$STATE_SECRETS/.sops.yaml" --encrypt \
        --input-type binary --output-type binary "$src" \
        > "$STATE_SECRETS/$name.enc.tmp" \
        || { rm -f "$STATE_SECRETS/$name.enc.tmp"; die "persist of $name failed (the previous .enc is left INTACT)"; }
    # roundtrip ALWAYS (the artifact's rule), against the .tmp:
    sops --decrypt --input-type binary --output-type binary \
        "$STATE_SECRETS/$name.enc.tmp" | cmp -s - "$src" \
        || { rm -f "$STATE_SECRETS/$name.enc.tmp"; die "the store's roundtrip failed for $name (the previous .enc is left INTACT)"; }
    mv "$STATE_SECRETS/$name.enc.tmp" "$STATE_SECRETS/$name.enc"
    log_info "persisted encrypted: $name (re-runs reuse it)"
}

restore_secret() {   # restore_secret <name> [dest-in-tmpfs]
    # Codes: 0 restored; 1 does NOT exist (the caller may generate);
    # 2 it EXISTS but does not decrypt. Run #11: sops failed MUTELY (0
    # chars, the age key's environment) and "does not decrypt" was
    # treated the same as "does not exist" → the caller REGENERATED —
    # exactly what the store exists to prevent (HMACs/keys already
    # registered with third parties; in phase 80 it would invalidate
    # the cosign signatures). The 2 travels with sops' error on
    # stderr, VISIBLE even when the caller captures stdout with $():
    local name="$1" dest="$SECRETS_TMP/${2:-$1}"
    sops_env
    [[ -f "$STATE_SECRETS/$name.enc" ]] || return 1
    if ! sops --decrypt --input-type binary --output-type binary \
            "$STATE_SECRETS/$name.enc" > "$dest" 2>"$dest.sops-err" \
       || [[ ! -s "$dest" ]]; then
        log_error "store: $name.enc EXISTS but sops did NOT decrypt it — it is NOT regenerated. Does SOPS_AGE_KEY_FILE point at the right key? (expected: ~/.config/sops/age/aegis.key). sops' stderr:"
        head -c 400 "$dest.sops-err" >&2 || true
        echo >&2
        rm -f "$dest" "$dest.sops-err"
        return 2
    fi
    rm -f "$dest.sops-err"
    chmod 600 "$dest"
    log_info "restored from the store: $name (not regenerated)"
    printf '%s' "$dest"
}

# store_rc_guard <rc> <name> — the guardian of code 2: callers that
# GENERATE when "restore failed" must tell absence (rc 1, generating
# is correct) from does-not-decrypt (rc 2, generating overwrites a
# live secret). A single point, so the die is not repeated in every
# caller:
store_rc_guard() {
    (( ${1:-0} != 2 )) || die "store: '$2' exists encrypted but does not decrypt — fix the age key's environment and re-run the phase (regenerating it would desynchronise third parties/signatures)"
}

# gen_or_restore <name> <gen_fn> [args...] — the canonical form:
# restores it if it exists; if not, generates it with the given fn AND
# persists it. Returns the path in tmpfs. Structural idempotence of
# secrets.
gen_or_restore() {
    local name="$1" gen_fn="$2"; shift 2
    local out rc=0
    out="$(restore_secret "$name")" || rc=$?
    store_rc_guard "$rc" "$name"        # rc 2 = does-not-decrypt: STOP
    if (( rc == 0 )); then
        printf '%s' "$out"; return 0
    fi
    out="$("$gen_fn" "$name" "$@")"
    persist_secret "$name" "$out"
    printf '%s' "$out"
}

# variant for SSH keypairs (two files, private + .pub):
gen_or_restore_keypair() {   # <name> <comment>
    local name="$1" comment="$2" priv rc=0
    priv="$(restore_secret "$name")" || rc=$?
    store_rc_guard "$rc" "$name"        # rc 2 = does-not-decrypt: STOP
    if (( rc == 0 )); then
        rc=0
        restore_secret "$name.pub" "$name.pub" >/dev/null || rc=$?
        store_rc_guard "$rc" "$name.pub"
        if (( rc != 0 )); then
            # P2.2 audit 2026-07-18: here the WHOLE pair got
            # REGENERATED just for a missing .pub — desynchronising
            # the live deploy key on GitHub (the private one was still
            # valid). The public one is DERIVED from the private one,
            # which is the source of truth (the comment from the
            # original -C is lost: cosmetic; the registered key does
            # not change):
            log_warn "store without $name.pub — I DERIVE the public one from the existing private one (the pair is not regenerated: the registered deploy key is still valid)"
            ssh-keygen -y -f "$priv" > "$priv.pub" \
                || die "could not derive the public key of $name — corrupt private key in the store?"
            persist_secret "$name.pub" "$priv.pub"
        fi
    else
        priv=""
    fi
    if [[ -z "${priv:-}" ]]; then
        priv="$(gen_ssh_keypair "$name" "$comment")"
        persist_secret "$name" "$priv"
        persist_secret "$name.pub" "$priv.pub"
    fi
    printf '%s' "$priv"
}

# ── generation (the right entropy per type) ─────────────────────────
# Each generator writes to ONE file in $SECRETS_TMP and returns the
# path. It NEVER prints the value. The length is reported with wc -c
# (an allowed shape-check: length only).

gen_hex32() {           # webhook HMACs (ArgoCD, Jenkins) — 32 bytes hex
    local out="$SECRETS_TMP/$1"
    # run #12 (the root bug of phase 60): `openssl rand -hex 32 > out`
    # leaves a trailing \n. The K8s Secret is byte-preserving (it keeps
    # it) but GitHub/gh api trim their side → the TWO sides of the HMAC
    # differ by ONE byte → different signatures → a deterministic 400
    # on EVERY delivery. tr -d '\n' = byte-identical on both sides:
    openssl rand -hex 32 | tr -d '\n' > "$out"
    log_info "generated $1 ($(wc -c < "$out") bytes)"
    printf '%s' "$out"
}

# assert_no_newline <path> [label] — run #12: a TEXT secret that
# travels to TWO sides (a byte-preserving K8s Secret vs an external
# API that trims) must be free of a trailing \n or the sides diverge
# in silence. It also catches OLD material from the store (generated
# with the pre-fix gen_hex32 and RESTORED byte-identical on re-runs):
assert_no_newline() {
    local f="$1" label="${2:-$1}"
    [[ "$(tail -c1 "$f" | od -An -tx1 | tr -d ' \n')" != "0a" ]] || \
        die "$label ends in \\n (0x0a) — an asymmetric HMAC between the K8s Secret and GitHub (run #12). If it comes from the old store: delete .state-secrets/${label}.enc and re-run the phase to regenerate it clean (WATCH OUT: it re-synchronises the webhook via PATCH, and the Jenkins plugin loads the HMAC at boot — restart the statefulset if Jenkins is already running)"
}

gen_password_b64() {    # random passwords (htpasswd, jenkins-admin)
    local out="$SECRETS_TMP/$1"
    openssl rand -base64 32 | tr -d '\n' > "$out"
    log_info "generated $1 ($(wc -c < "$out") bytes)"
    printf '%s' "$out"
}

gen_ssh_keypair() {     # deploy keys — ed25519 with no passphrase
    local name="$1" comment="$2"
    ssh-keygen -t ed25519 -N "" -C "$comment" -f "$SECRETS_TMP/$name" \
        -q
    log_info "keypair $name generated (pub: $(cut -d' ' -f1,2 \
        < "$SECRETS_TMP/$name.pub" | head -c 40)...)"
    printf '%s' "$SECRETS_TMP/$name"     # private; public in .pub
}

gen_age_key() {         # THE root of trust
    # It does NOT set variables in the parent (H4 of validation #1:
    # the function runs in the $()'s subshell and any variable dies
    # there). The public one is derived by the CALLER from the file,
    # with the official tool: AGE_PUBLIC="$(age-keygen -y "$path")".
    local out="$SECRETS_TMP/age.key"
    age-keygen -o "$out" 2>/dev/null
    log_info "age key generated in tmpfs"
    printf '%s' "$out"
}

gen_cosign_keypair() {  # signing authority. Password: see the ceremony.
    # Baked-in pothole A43: in a container, run it with
    #   --user "$(id -u):$(id -g)" or the keypair ends up owned by 65532.
    local passfile="$1"   # file with the password (from
                          # gen_password_b64 or prompt_secret_manual)
    ( cd "$SECRETS_TMP" && \
      COSIGN_PASSWORD="$(cat "$passfile")" cosign generate-key-pair )
    log_info "cosign keypair generated (cosign.key/cosign.pub in tmpfs)"
}

# materialize <filename> <value> — writes a NON-secret auxiliary value
# (url, name, type, ids) to tmpfs byte-preserving (no \n) and returns
# the path. It exists so the key=path pairs that make_enc_secret
# consumes have their file ready BEFORE encrypting — the ordering bug
# that motivated this helper was real (phase 15, || true).
materialize() {
    local out="$SECRETS_TMP/$1"; shift
    printf '%s' "$*" > "$out"
    printf '%s' "$out"
}

# manual entry = an EXCEPTION. Typed twice + minimum length. No echo.
# (the newline echoes go to STDERR — stdout returns the path and
#  NOTHING else; H4 of validation #1)
prompt_secret_manual() {
    local label="$1" minlen="${2:-16}" out="$SECRETS_TMP/$3"
    local v1 v2
    while :; do
        read -rsp "value for ${label}: " v1 \
            || die "stdin closed asking for ${label} — unattended, this value comes in by file (see --non-interactive)"
        echo >&2
        read -rsp "repeat ${label}: " v2 \
            || die "stdin closed asking for ${label}"
        echo >&2
        [[ "$v1" == "$v2" ]] || { log_warn "they do not match; again"; continue; }
        (( ${#v1} >= minlen )) || { log_warn "minimum ${minlen} chars"; continue; }
        break
    done
    printf '%s' "$v1" > "$out"
    unset v1 v2
    printf '%s' "$out"
}

# ── atomic derivations (same process, one origin) ───────────────────
# derive_htpasswd_and_regcreds: from the registry password it derives
# the htpasswd AND the 4 dockerconfigjson IN THE SAME CALL. It is
# impossible to generate "one side" on its own — the atomicity is
# structural (27 §2a.M2).
derive_htpasswd_and_regcreds() {
    local user="$1" passfile="$2" registry_host="$3"
    # bcrypt htpasswd through stdin (never argv):
    htpasswd -nBi "$user" < "$passfile" > "$SECRETS_TMP/htpasswd"
    # dockerconfigjson (jq builds the JSON; the value never passes
    # through an external process' argv — jq reads it with --rawfile):
    jq -n --rawfile pass "$passfile" \
          --arg user "$user" --arg host "$registry_host" \
          '{auths: {($host): {username: $user, password: ($pass),
            auth: (($user + ":" + $pass) | @base64)}}}' \
        > "$SECRETS_TMP/dockerconfig.json"
    log_info "htpasswd + dockerconfigjson derived from the SAME origin"
}

# ── packaging into an encrypted K8s Secret (KSOPS) ──────────────────
# make_enc_secret: kubectl --from-file (data:, byte-preserving) →
# mv to the REPO PATH → sops -e --in-place → validation ROUNDTRIP.
# The order is rule A5/A6 encoded; there is no way to use it wrong.
#   usage: make_enc_secret <name> <ns> <repo_dest.enc.yaml> \
#          [--type <k8s-secret-type>] [--label k=v]... \
#          [--annotation k=v]... key=path...
# --type (run #9): `create secret generic` produces type OPAQUE, and
# imagePullSecrets ONLY works with kubernetes.io/dockerconfigjson —
# the kubelet IGNORES an Opaque as a pull secret ("no basic auth
# credentials") even though the SAME secret works mounted as a volume.
# The type stays in cleartext after SOPS (encrypted_regex = ^(data|
# stringData)$). Remember A34: type is IMMUTABLE — changing the type
# of an already-live Secret requires kubectl delete + re-sync.
make_enc_secret() {
    local name="$1" ns="$2" dest="$3"; shift 3
    local args=() labels=() annots=()
    while (($#)); do case "$1" in
        --type)       args+=(--type="$2"); shift 2 ;;
        --label)      labels+=("$2"); shift 2 ;;
        --annotation) annots+=("$2"); shift 2 ;;
        *)            args+=(--from-file="$1"); shift ;;
    esac; done
    local tmp_yaml="$SECRETS_TMP/${name}.yaml"
    kubectl create secret generic "$name" -n "$ns" \
        --dry-run=client -o yaml "${args[@]}" > "$tmp_yaml"
    local kv
    for kv in "${labels[@]:-}"; do [[ -n "$kv" ]] && \
        kubectl label -f "$tmp_yaml" --local --dry-run=client -o yaml \
            "$kv" > "$tmp_yaml.n" && mv "$tmp_yaml.n" "$tmp_yaml"; done
    for kv in "${annots[@]:-}"; do [[ -n "$kv" ]] && \
        kubectl annotate -f "$tmp_yaml" --local --dry-run=client -o yaml \
            "$kv" > "$tmp_yaml.n" && mv "$tmp_yaml.n" "$tmp_yaml"; done
    # A5: FIRST into the repo (.sops.yaml's path_regex), THEN encrypt
    # (through the helper with an explicit --config — pattern A of
    # validation #3):
    mv "$tmp_yaml" "$dest"
    sops_encrypt_repo "$dest"
    # roundtrip ALWAYS — validates rule and recipient without showing values:
    sops -d "$dest" | grep -q '^kind: Secret' \
        || die "SOPS roundtrip failed for $dest"
    log_ok "Secret $ns/$name encrypted into $dest (roundtrip OK)"
}

# ── registry credentials for the init's gates ───────────────────────
# registry_creds <reg_host:port> <cluster_ip>: materialises them in
# tmpfs, reading from the cluster (mechanics, without showing values —
# the no-print rule):
#   $SECRETS_TMP/registry.netrc   (curl --netrc-file; machine = the host
#                                  and also the IP, for gates that go
#                                  by --resolve or by direct IP)
#   $SECRETS_TMP/aegis-ca.crt     (T1 CA → --cacert / --registry-cacert)
#   $SECRETS_TMP/docker/config.json (DOCKER_CONFIG for cosign; auths
#                                  keyed by host AND by IP)
registry_creds() {
    local reg_host="$1" cluster_ip="$2"
    kubectl -n jenkins-system get secret regcred-internal \
        -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d \
        > "$SECRETS_TMP/dockercfg.json"
    mkdir -p "$SECRETS_TMP/docker"
    python3 - "$SECRETS_TMP/dockercfg.json" "$reg_host" "$cluster_ip" \
        "$SECRETS_TMP/registry.netrc" "$SECRETS_TMP/docker/config.json" <<'EOF'
import base64, json, sys
src, reg_host, ip, netrc_out, cfg_out = sys.argv[1:6]
port = reg_host.rsplit(":", 1)[1]
cfg = json.load(open(src))
auth = cfg["auths"][reg_host]["auth"]
user, pw = base64.b64decode(auth).decode().split(":", 1)
with open(netrc_out, "w") as f:
    f.write(f"machine {reg_host.split(':')[0]} login {user} password {pw}\n")
    f.write(f"machine {ip} login {user} password {pw}\n")
json.dump({"auths": {reg_host: {"auth": auth},
                     f"{ip}:{port}": {"auth": auth}}}, open(cfg_out, "w"))
EOF
    chmod 600 "$SECRETS_TMP/registry.netrc" "$SECRETS_TMP/docker/config.json"
    kubectl -n cert-manager get secret aegis-internal-ca \
        -o jsonpath='{.data.ca\.crt}' | base64 -d > "$SECRETS_TMP/aegis-ca.crt"
    log_info "registry creds materialised in tmpfs (netrc+CA+docker cfg)"
}

# ── backup ceremony (the irreplaceables) ────────────────────────────
# ceremony_backup: "SAVE THIS NOW — IT IS NOT SHOWN AGAIN".
# The value is shown ONCE (that is the deliberate exception: the
# OPERATOR has to see it in order to save it — the
# secret-to-the-operator principle) and the backup is VALIDATED by a
# real roundtrip, not by a confirmation:
#   - age key: encrypt a canary with the public key → the operator
#     decrypts using ONLY the backed-up copy (rotate-age-key.md
#     §A.8/A.9).
#   - cosign: sign a blob → verify with the pub + the password
#     RE-TYPED from the backup.
#   - write key: fingerprint shown; the operator re-reads it from
#     GitHub after registering it and the init compares.
# gate_red ALWAYS before showing (RED: deliberate exposure).
ceremony_backup() {
    local label="$1" file="$2" validate_fn="$3"
    # P0.3 audit 2026-07-18 — the UNATTENDED path: there is no operator
    # watching the screen. The backup goes to AEGIS_AGE_BACKUP_FILE
    # (a path the LAUNCHER chose, ideally its own tmpfs); moving it to
    # a real backup is the responsibility of whoever launched the run.
    # The validation roundtrip is still REAL (validate_fn reads from
    # that file):
    if ni_mode; then
        : "${AEGIS_AGE_BACKUP_FILE:?--non-interactive requires AEGIS_AGE_BACKUP_FILE (destination of the age key's backup, ideally in the launcher's /dev/shm)}"
        [[ "$AEGIS_AGE_BACKUP_FILE" == /dev/shm/* ]] || \
            log_warn "AEGIS_AGE_BACKUP_FILE outside /dev/shm — it is going to touch persistent disk; move it to a backup and delete it with shred"
        run_cmd install -m 600 "$file" "$AEGIS_AGE_BACKUP_FILE"
        log_warn "backup of ${label} WRITTEN to $AEGIS_AGE_BACKUP_FILE — move it to your real backup and destroy the copy NOW"
        gate "resguardo-${label}" "$validate_fn"
        return 0
    fi
    # W-01 / EV-01 (2026-07-21): the key is NEVER printed to the pane.
    # tmux pipe-pane, script(1), asciinema and agent transcripts record
    # the whole pane, and the old guard [[ -t 1 ]] does not detect the
    # class (under tmux stdout IS STILL a TTY, and clear does not wipe
    # the scrollback). The robust model: the value does not travel
    # through the shared channel — it is written to tmpfs and the
    # operator reads it from ANOTHER terminal, outside this pane. It is
    # the SAME mechanism as the --non-interactive path above. The
    # validation roundtrip is kept.
    local shm_out="/dev/shm/aegis-resguardo-$$"   # without $label: EV-12
    ( umask 077; run_cmd install -m 600 "$file" "$shm_out" )
    gate_red "Backup of ${label}: it is read from ANOTHER terminal, NOT in this pane"
    human_step "Backup of ${label} (HOW, step by step)" \
        "1. Open ANOTHER terminal on this host (NOT this init pane)." \
        "2. Run there:  cat $shm_out" \
        "3. Save the value wherever you keep your secrets (a manager," \
        "   paper, a USB stick — the init assumes none of them)." \
        "4. Next, the init ASKS YOU FOR IT AGAIN from your copy in" \
        "   order to validate the backup for real (roundtrip)." \
        "5. The init destroys the /dev/shm copy as soon as you validate."
    # REAL validation of the backup — the operator uses THEIR COPY:
    gate "resguardo-${label}" "$validate_fn"
    run_cmd rm -f "$shm_out"   # tmpfs: rm frees it; shred is cosmetic (M1.11)
}

# ceremony validators (one per irreplaceable):
validate_age_backup() {
    # a canary encrypted with the public key; decrypt it ONLY with the
    # copy the operator says they have backed up. GUIDED (H5 of
    # validation #1): the init ASKS for the key at a prompt — the
    # operator pastes one line, does not edit files. Plan B is
    # documented in the prompt itself.
    local canary="$SECRETS_TMP/canary.txt"
    echo "aegis-init-canary-$$" > "$canary"
    # unattended path (P0.3): the backed-up copy IS the file that
    # ceremony_backup wrote — the roundtrip uses it directly:
    if ni_mode; then
        ( cd "$SECRETS_TMP" && \
          sops --encrypt --age "$AGE_PUBLIC" "$canary" > "$canary.enc" )
        SOPS_AGE_KEY_FILE="$AEGIS_AGE_BACKUP_FILE" \
            sops -d "$canary.enc" | grep -q "aegis-init-canary-$$"
        return $?
    fi
    # cd to tmpfs for the encrypt: even with an explicit --age, sops
    # looks for a .sops.yaml from the CWD upwards and if it finds one
    # whose path_regex does not match it FAILS ("no matching creation
    # rules") — caught by validation #4's harness running from a
    # workspace with its own .sops.yaml. /dev/shm has none:
    ( cd "$SECRETS_TMP" && \
      sops --encrypt --age "$AGE_PUBLIC" "$canary" > "$canary.enc" )
    printf '\nREAL validation of the backup: you are going to paste the key\n' >&2
    printf 'FROM YOUR BACKED-UP COPY (not from this screen).\n' >&2
    printf 'It is the line that starts with AGE-SECRET-KEY-1...\n' >&2
    printf '(to paste: right click or Ctrl+Shift+V; it is not shown).\n' >&2
    printf 'Plan B if the paste does not work: in ANOTHER terminal run\n' >&2
    printf '  nano %s/age.restored\n' "$SECRETS_TMP" >&2
    printf 'paste the line, Ctrl+O + Enter, Ctrl+X, and here press Enter\n' >&2
    printf 'with the prompt empty.\n\n' >&2
    local pasted
    read -rsp "paste the AGE-SECRET-KEY from your backup: " pasted \
        || { log_warn "stdin closed during the backup validation"; return 1; }
    echo >&2
    if [[ -n "$pasted" ]]; then
        printf '%s\n' "$pasted" > "$SECRETS_TMP/age.restored"
        unset pasted
    fi
    chmod 600 "$SECRETS_TMP/age.restored" 2>/dev/null
    [[ -s "$SECRETS_TMP/age.restored" ]] || {
        log_warn "no key pasted and no file either (plan B)"; return 1; }
    SOPS_AGE_KEY_FILE="$SECRETS_TMP/age.restored" \
        sops -d "$canary.enc" | grep -q "aegis-init-canary-$$"
}
# (validate_cosign_backup REMOVED in D11: the cosign ceremony no
# longer exists — the keypair and the password live in the encrypted
# store and are recovered with the age key, the only irreducible.)
