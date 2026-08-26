#!/usr/bin/env bash
# aegis-init lib/common.sh — logging, gates, human pauses, state.
# Loaded by aegis-init.sh; the phases receive it already sourced.
# Baked-in rules: revert steps NEVER with && (every step with a
# visible exit code); GREEN/YELLOW/RED levels as gate functions.

set -euo pipefail

: "${AEGIS_ROOT:?common.sh requires AEGIS_ROOT (the PRODUCT). bin/aegis exports it; a libexec invoked by hand resolves it with readlink -f of its own path}"

# Product and instance: one single resolver, in lib/paths.sh (02 §1).
# shellcheck source=paths.sh
source "$AEGIS_ROOT/lib/paths.sh"

: "${CHECK_MODE:=false}"
: "${PROFILE:=greenfield}"
: "${AEGIS_NONINTERACTIVE:=false}"

# ── platform constants (P3 of the 2026-07-18 audit) ─────────────────
# REG_HOST was duplicated BY HAND across 4 phases (40/50/70/80) — one
# divergence would break cert/mirror/netrc/policy all at once. Single
# source:
REGISTRY_HOST_INTERNAL="registry.registry-system.svc.cluster.local:5000"

# ── unattended mode (P0.1 of the 2026-07-18 audit) ──────────────────
# ni_mode: --non-interactive / AEGIS_ASSUME_YES=true. The init runs
# from 0 to the end WITHOUT an operator: human_step and gate_red
# self-confirm (the authorisation was given by the flag — meant for a
# DISPOSABLE greenfield VM and for the init's own CI). The input
# secrets go in by file (CF_MASTER_FILE / AEGIS_AGE_BACKUP_FILE,
# tmpfs).
# The deliberate EXCEPTION: decisions that could tread on resources
# NOT marked as disposable (a repo with no marker) DIE instead of
# self-confirming — unattended is not a blank cheque over what belongs
# to someone else.
ni_mode() { [[ "${AEGIS_NONINTERACTIVE:-false}" == "true" ]]; }

# ── logging ─────────────────────────────────────────────────────────
# EVERY log goes to STDERR (finding 4 of validation #1): the stdout of
# a function-that-returns-a-value is SACRED — capturing it with $()
# must give ONLY the value. A log_info on stdout inside gen_*
# contaminated the returned path and broke the age key ceremony.
# verify-static watches that this convention does not come back
# (check 14).
_ts() { date '+%H:%M:%S'; }
log_info()  { printf '\033[1;34m[%s INFO ]\033[0m %s\n' "$(_ts)" "$*" >&2; }
log_ok()    { printf '\033[1;32m[%s  OK  ]\033[0m %s\n' "$(_ts)" "$*" >&2; }
log_warn()  { printf '\033[1;33m[%s WARN ]\033[0m %s\n' "$(_ts)" "$*" >&2; }
log_error() { printf '\033[1;31m[%s ERROR]\033[0m %s\n' "$(_ts)" "$*" >&2; }
die()       { log_error "$*"; exit 1; }

phase_todo() { log_warn "TODO: $*"; }

# ── per-phase state (for --from and the summary) ────────────────────
# One marker file per completed phase. Cheap, legible idempotence.
mark_done()   { mkdir -p "$AEGIS_STATE_DIR"; : > "$AEGIS_STATE_DIR/$1.done"; }
is_done()     { [[ -f "$AEGIS_STATE_DIR/$1.done" ]]; }
# --reset-state forgets the GATES, not the HISTORY. runs/ holds the
# dossier of every run made so far, and until 2026-08-26 this was a plain
# `rm -rf "$AEGIS_STATE_DIR"`: the flag whose whole job is "start over"
# also destroyed the only record of what had happened before — including
# the dossier of the run that made you want to start over. The gates being
# forgotten are ARCHIVED, not deleted: "what did it say last time" is a
# question that has to survive a reset (plan/04 §5).
clear_state() {
    [[ -d "$AEGIS_STATE_DIR" ]] || return 0
    local runs="$AEGIS_STATE_DIR/runs" stamp
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    if [[ -f "$AEGIS_STATE_DIR/gates.jsonl" ]]; then
        mkdir -p "$runs/_reset-$stamp"
        mv "$AEGIS_STATE_DIR/gates.jsonl" "$runs/_reset-$stamp/gates.jsonl"
    fi
    find "$AEGIS_STATE_DIR" -mindepth 1 -maxdepth 1 ! -name runs -exec rm -rf {} +
}

# ── check mode ──────────────────────────────────────────────────────
# run_cmd: in CHECK_MODE it shows without executing. ONLY for commands
# that MUTATE. Reads are always executed (a dry-run that does not read
# validates nothing — the check_mode lesson from Ansible, 2026-05-01).
run_cmd() {
    if [[ "$CHECK_MODE" == "true" ]]; then
        log_info "[check] $*"
    else
        "$@"
    fi
}

# ── human pauses ────────────────────────────────────────────────────
# human_step: the ONLY way to ask for an external action. It shows
# WHAT to do, WHERE, and waits for confirmation. It never reads the
# secret value here (that belongs to lib/secrets.sh, which does not
# show it).
human_step() {
    local title="$1"; shift
    printf '\n\033[1;35m══ HUMAN ACTION ══ %s\033[0m\n' "$title"
    printf '%s\n' "$@"
    if [[ "$CHECK_MODE" == "true" ]]; then
        log_info "[check] (human pause skipped)"
        return 0
    fi
    if ni_mode; then
        log_info "(--non-interactive: human pause self-confirmed)"
        return 0
    fi
    # || die (P0 of the audit): with no TTY, read gets EOF and with
    # errexit alive the phase died with a mute error — the die says
    # the cause:
    read -rp $'\nReady? [enter to continue / ctrl-c to abort] ' _ \
        || die "stdin closed at a human pause — with no terminal, run with --non-interactive"
}

# ── machine-readable record of gates (P2.13 in-VM report #14) ───────
# Every gate appends ONE JSON line to $AEGIS_STATE_DIR/gates.jsonl
# (ts, phase, gate, result, duration): an agent diagnoses historical
# runs with jq, without parsing the ANSI of the human log. The gate
# names are fixed slugs (no quotes, no backslashes) — a plain printf
# is enough, no serialiser needed. Best-effort on purpose: the record
# may NEVER flip a gate:
_gate_record() {   # <gate> <pass|fail> <duration_s>
    { mkdir -p "$AEGIS_STATE_DIR" && \
      printf '{"ts":"%s","phase":"%s","gate":"%s","result":"%s","duration_s":%s}\n' \
        "$(date -u +%FT%TZ)" "${AEGIS_PHASE:-}" "$1" "$2" "$3" \
        >> "$AEGIS_STATE_DIR/gates.jsonl"; } 2>/dev/null || true
}

# ── gates ───────────────────────────────────────────────────────────
# gate_no_subject: the gate has NOTHING TO LOOK AT under this edge.
#
# It is the third outcome applied to a gate, and it exists because the
# alternative is worse than a red: a gate that simply STOPS being
# written disappears from gates.jsonl, and three months later a missing
# line reads exactly like a green one. Whoever reads the record has to
# be able to tell "it passed" from "nobody asked the question".
#
# It is NOT an approval, and the log says so out loud. The reason is
# written whole — "EDGE=local: there is no zone to write a record into"
# and never "skipped" — because the reason is the only thing that makes
# the absence auditable later.
#
# It landed here on 2026-08-26 after two phases wrote the same helper,
# separately, with the same name and the same signature: two copies of
# one idea is how the vocabulary drifts, and the day they drift the
# record has two words for the same silence.
gate_no_subject() {   # <gate> <reason...>
    local name="$1"; shift
    _gate_record "$name" not-evaluated 0
    log_warn "GATE $name NOT EVALUATED — $*"
    log_warn "  (this is a NOTICE, not an approval: nobody measured it)"
}

# gate: a check with evidence. It fails the phase if the gate fails.
# The name stays in the log — the gates are each phase's contract.
gate() {
    local name="$1"; shift
    local t0=$SECONDS
    if "$@"; then
        _gate_record "$name" pass $(( SECONDS - t0 ))
        log_ok "GATE $name"
    else
        _gate_record "$name" fail $(( SECONDS - t0 ))
        die "GATE $name FAILED — the phase cannot continue"
    fi
}

# ── a REAL entry in a YAML list (H4 run #13, a SYSTEMIC bug) ────────
# The idempotence guards of the same-commit steps used a `grep -q` of
# the file's NAME — but the COMMENT that documents the pattern
# contains that very name → the guard matched the comment → the step
# was left "already done" → the entry was NEVER added → an orphaned
# resource with no clue (the case that motivated it: the Image
# Updater's CR and its regcred, both retired in #59;
# 2 latent ones: cosign and the signature policy). Mention ≠ use,
# applied to YAML: only the list ENTRY counts (`- file`), never the
# comment. EVERY same-commit guard goes through here (check 41):
yaml_lists_file() {   # <yaml> <basename>
    # Tolerates a comment at the end of the line. Without the
    # `(#.*)?`, a documented entry (`- x.enc.yaml  # phase 85 encrypts
    # it`) was invisible to the guard and the phase inserted it AGAIN
    # — kustomize died with «already registered id» on the first
    # ignition of phase 85 (2026-08-20). The comment is valid YAML;
    # the guard had to read YAML, not lines.
    grep -qE "^\s*-\s*${2//./\\.}\s*(#.*)?$" "$1"
}

# ── does this manifest hold any object? (A/B of the H4) ─────────────
# A DERIVED manifest can legitimately be empty: its documents come out
# of something else, and that something else may not exist yet. The
# case: k8s/bootstrap/appprojects-tenants.yaml is generated by
# `aegis org` from orgs/*.yaml, and a freshly started instance has
# ZERO contracts — the file arrives with its header and without a
# single document. `kubectl apply -f` over that is NOT a no-op:
#
#     error: no objects passed to apply     (rc 1)
#
# and with set -e it kills phase 35. Which is to say the seed would
# not start up for the very reason that makes it correct.
#
# Structural and not textual, for the same reason as yaml_lists_file:
# the file's header NAMES the kinds it documents, so a
# `grep -q AppProject` would come out true over a file with no objects
# — the H4 again, this time in reverse.
yaml_has_docs() {   # <yaml>
    python3 - "$1" <<'EOF'
import sys, yaml
try:
    docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
except Exception as e:
    print(f"unreadable YAML: {e}", file=sys.stderr); sys.exit(2)
sys.exit(0 if docs else 1)
EOF
}

# ── multi-line placeholder injection (CR-1/CR-2 run #14) ────────────
# The SIBLING family of the H4, applied to the INJECTIONS: phase 80's
# global replace() dumped the PEM into the COMMENT that documented the
# placeholder as well (CR-1: broken top-level YAML, kustomize "missing
# Resource metadata") and the CA's next() took the indent of the FIRST
# occurrence — which was a comment — breaking the block scalar (CR-2:
# helm "did not find expected key"). Same class as H6 (multi-line
# material that does not respect the destination's structure). THE
# ONLY way to inject multi-line content into a YAML of the artifact
# (check 48):
#   (a) only NON-comment lines count (the comments are left intact,
#       whatever it is they document);
#   (b) EXACTLY ONE non-comment occurrence is demanded;
#   (c) the indent comes from THAT line (the real one, not a comment);
#   (d) the resulting YAML is VALIDATED before writing — if it does
#       not parse, the destination is left intact and the phase dies
#       here, not three gates later with a kustomize/helm error.
inject_placeholder() {   # <target_yaml> <placeholder> <content_file>
    python3 - "$1" "$2" "$3" <<'EOF'
import sys, yaml
target, ph, content_path = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(target).read()
lines = text.splitlines()
hits = [i for i, l in enumerate(lines)
        if ph in l and not l.lstrip().startswith("#")]
if len(hits) != 1:
    sys.exit(f"inject_placeholder: {ph} has {len(hits)} non-comment "
             f"occurrences in {target} (EXACTLY 1 is required)")
i = hits[0]
indent = lines[i][: len(lines[i]) - len(lines[i].lstrip())]
block = ("\n" + indent).join(open(content_path).read().strip().splitlines())
lines[i] = lines[i].replace(ph, block)
out = "\n".join(lines) + ("\n" if text.endswith("\n") else "")
try:
    list(yaml.safe_load_all(out))
except Exception as e:
    sys.exit(f"inject_placeholder: the YAML resulting from {target} does "
             f"NOT parse ({e}) — the file is left INTACT")
open(target, "w").write(out)
EOF
}

# idempotence guard for the injections: is there a LIVE (non-comment)
# occurrence of the placeholder left? On a re-run there is none left
# and the injection is skipped (inject_placeholder with 0 occurrences
# DIES on purpose — better explicit than silent):
placeholder_pending() {   # <yaml> <placeholder>
    grep -vE '^\s*#' "$1" | grep -qF "$2"
}

# ── gate with diagnosis on failure (H7 run #13) ─────────────────────
# Every MUTE timeout of run #13 had the exact error hidden away in a
# status (the App's operationState, the ns' events, the pod's
# describe). gate_diag = gate, but on failure it RUNS the given
# diagnosis before dying — the operator sees the cause, not just the
# name:
gate_diag() {   # <name> <diag_bash_string> <cmd...>
    local name="$1" diag="$2"; shift 2
    local t0=$SECONDS
    if "$@"; then
        _gate_record "$name" pass $(( SECONDS - t0 ))
        log_ok "GATE $name"
    else
        _gate_record "$name" fail $(( SECONDS - t0 ))
        log_warn "GATE $name failed — evidence:"
        # eval (not bash -c): the diagnosis may use functions from the
        # libs (jenkins_get, etc.), not only binaries:
        eval "$diag" >&2 || true
        die "GATE $name FAILED — the real cause is in the evidence above"
    fi
}

# gate_red: RED actions (irreversible/secrets) ALWAYS confirm, even
# when running "with no brakes". The init automates mechanics, not
# irreversible decisions (the secret-to-the-operator principle).
gate_red() {
    local why="$1"
    printf '\n\033[1;31m══ RED ══\033[0m %s\n' "$why"
    [[ "$CHECK_MODE" == "true" ]] && { log_info "[check] (red skipped)"; return 0; }
    # P0.1 of the audit: in --non-interactive the RED self-confirms —
    # the deliberate affirmation was given by the operator WHEN
    # PASSING THE FLAG (contract: a disposable greenfield VM / the
    # init's CI). It is logged LOUDLY so that gates.jsonl and the log
    # keep a trace of what was self-approved. Decisions about someone
    # else's resources do not come through here in NI (the callers die
    # earlier — see ensure_repo, phase 12):
    if ni_mode; then
        log_warn "RED self-confirmed by --non-interactive: $why"
        return 0
    fi
    # the security property is the DELIBERATE affirmation (the whole
    # word), not the case of the letters (H3 validation #1: "si" in
    # lower case aborted with no explanation). A single letter or a
    # bare Enter is not accepted:
    local ans
    read -rp 'Type YES (upper or lower case) to continue — anything else aborts: ' ans \
        || die "stdin closed at a RED gate — with no terminal, run with --non-interactive"
    [[ "${ans^^}" == "YES" ]] || die "Aborted by the operator at a RED gate"
}

# ── rendering of config-class placeholders ──────────────────────────
# render_platform_placeholders: THE ONLY owner of the replacement of
# the placeholders derivable from aegis-init.conf/$PROFILE inside
# platform/ (T1). The generated-class ones have an owning phase and
# are NOT touched here: __AGE_PUBLIC__ (phase 10), __COSIGN_PUB__ and
# __AEGIS_CA_PEM__ (phase 80), __OBS_CA_PEM__ and
# __OBS_NTFY_{OPERADOR,PUENTE}_HASH__ (phase 85). Idempotent: with no
# live placeholders it is a no-op. At the end it verifies that not one
# config-class placeholder survives (an explicit failure, not a
# half-rendered manifest).
#
# The 5 observability ones are DERIVED from $PROFILE (phase-85 §4:
# concrete values per placeholder, not a profile-name that would
# demand new templating machinery). The profile is an identity of
# BIRTH: changing --profile on a re-run does NOT re-render (the
# placeholder is already dead) — changing it afterwards means editing
# the values in git. Table (consumers in k8s/base/observability/):
#
#   placeholder                 greenfield  hetzner  consumer
#   __AEGIS_PROFILE__           greenfield  hetzner  vmagent's external_labels (the identity of the data)
#   __OBS_RETENCION_METRICAS__  30d         90d      vmsingle retentionPeriod
#   __OBS_RETENCION_LOGS__      7d          30d      vlogs retentionPeriod
#   __OBS_CF_CAIDO_FOR__        30m         5m       cloudflared rule (for:) — dev goes down by design
#   __OBS_DEADMAN_REPEAT__      24h         6h       the deadman's route (repeat_interval) — at 6h in dev
#                                                    the operator would learn to ignore the nightly gap
#
# (the retention of events, 1y, is NOT a placeholder: it does not vary
#  by profile — a constant value dressed up as a variable is a lie
#  about flexibility)
_CONFIG_PLACEHOLDERS='__\(GH_OWNER\|PLATFORM_REPO\|APP_REPO\|ROOT_DOMAIN\|REGISTRY_CLUSTER_IP\|ACME_EMAIL\|AEGIS_PROFILE\|OBS_RETENCION_METRICAS\|OBS_RETENCION_LOGS\|OBS_CF_CAIDO_FOR\|OBS_DEADMAN_REPEAT\)__'
render_platform_placeholders() {
    : "${GH_OWNER:?}" "${PLATFORM_REPO:?}" "${APP_REPO:?}" \
      "${ROOT_DOMAIN:?}" "${REGISTRY_CLUSTER_IP:?}" "${ACME_EMAIL:?}" \
      "${PROFILE:?}"
    local obs_ret_metrics obs_ret_logs obs_cf_down_for obs_deadman_repeat
    case "$PROFILE" in
        hetzner) obs_ret_metrics=90d obs_ret_logs=30d
                 obs_cf_down_for=5m  obs_deadman_repeat=6h ;;
        *)       obs_ret_metrics=30d obs_ret_logs=7d
                 obs_cf_down_for=30m obs_deadman_repeat=24h ;;
    esac
    local f
    while IFS= read -r f; do
        run_cmd sed -i \
            -e "s|__GH_OWNER__|$GH_OWNER|g" \
            -e "s|__PLATFORM_REPO__|$PLATFORM_REPO|g" \
            -e "s|__APP_REPO__|$APP_REPO|g" \
            -e "s|__ROOT_DOMAIN__|$ROOT_DOMAIN|g" \
            -e "s|__REGISTRY_CLUSTER_IP__|$REGISTRY_CLUSTER_IP|g" \
            -e "s|__ACME_EMAIL__|$ACME_EMAIL|g" \
            -e "s|__AEGIS_PROFILE__|$PROFILE|g" \
            -e "s|__OBS_RETENCION_METRICAS__|$obs_ret_metrics|g" \
            -e "s|__OBS_RETENCION_LOGS__|$obs_ret_logs|g" \
            -e "s|__OBS_CF_CAIDO_FOR__|$obs_cf_down_for|g" \
            -e "s|__OBS_DEADMAN_REPEAT__|$obs_deadman_repeat|g" \
            "$f"
        log_info "render: ${f#"$PLATFORM_DIR"/}"
    done < <(grep -rl "$_CONFIG_PLACEHOLDERS" "$PLATFORM_DIR" \
             --exclude='*.tpl' 2>/dev/null || true)
    if [[ "$CHECK_MODE" != "true" ]] && \
       grep -rq "$_CONFIG_PLACEHOLDERS" "$PLATFORM_DIR" --exclude='*.tpl'; then
        grep -rl "$_CONFIG_PLACEHOLDERS" "$PLATFORM_DIR" --exclude='*.tpl'
        die "incomplete render: config-class placeholders are left over"
    fi
}

# poll <timeout_s> <every_s> <cmd...> — retries until the command
# passes or the timeout expires. For long waits (builds, rollouts
# outside kubectl wait); retry_net is for one-off egress.
poll() {
    local timeout="$1" every="$2"; shift 2
    # P3 of the audit: the old `waited` did NOT count the command's
    # duration (a 20s probe made "300s of timeout" into 300s of sleep
    # + N×20s of probes). SECONDS measures REAL elapsed time:
    local t0=$SECONDS
    until "$@"; do
        (( SECONDS - t0 >= timeout )) && return 1
        sleep "$every"
    done
}

# ── CANONICAL argo_sync (one single definition — bug C run #8) ──────
# History: every phase defined its own local argo_sync (patch + wait
# for health). Bug C: if the App was ALREADY Healthy (typical with
# --from), the health wait returns INSTANTLY without waiting for the
# sync just fired → the reading of operationState saw "Running" → a
# false-negative gate. And the patch against an App the root sync had
# not created yet failed with "not found" (timing pattern #8: retrying
# without changing anything "fixed" it).
# This argo_sync: (1) waits for the App to EXIST (poll — creation is
# async, done by the root); (2) fires the sync; (3) waits for the
# TERMINAL phase of the NEW operation — told apart from the previous
# one by startedAt, so an old Succeeded is not read as the result of
# the new sync — with a FAST cut on Failed/Error (a real failure ≠
# has-not-converged-yet); (4) only then does it demand Healthy.
# Returns 1 on failure (with a log) — set -e makes it fatal in the
# caller, and `argo_sync X || retry` allows deliberate retries.
argo_sync() {   # <app> [timeout_s]
    local app="$1" timeout="${2:-300}"
    log_info "sync $app"
    if ! poll 180 5 bash -c \
         "kubectl -n argocd get application '$app' -o name >/dev/null 2>&1"; then
        log_error "App $app does not exist after 180s (did the root sync run?)"
        _gate_record "sync-$app" fail 180
        return 1
    fi
    local prev_started
    prev_started="$(kubectl -n argocd get application "$app" \
        -o jsonpath='{.status.operationState.startedAt}' 2>/dev/null || true)"
    # P1.3 of the audit (a selfHeal race in flight, confirmed in the
    # real run): with automated+selfHeal an operation may be RUNNING
    # at the moment of the patch → ArgoCD rejects the patch with
    # "another operation is already in progress" and the sync died as
    # a real failure. That operation in progress IS the sync we want:
    # it is ADOPTED (prev_started="" makes any terminal phase count).
    # H5 run #15 (THE OVER-CORRECTION of bug C, it bit live: 17 mute
    # minutes + phase 50 dead with the system HEALTHY): the third case
    # is a patch ACCEPTED but a NO-OP — the App (automated) keeps a
    # residual `.operation` from the automatic sync, and merging an
    # empty sync over another sync changes NOTHING ("patched (no
    # change)") → there will never be a new startedAt → demanding a
    # "new operation" waits for something that is not going to exist.
    # The patch's output is captured in order to detect it; the
    # acceptance of the present state goes in the loop (new rule:
    # every race fix with an "it is new" condition contemplates the
    # case "the desired state ALREADY existed"):
    if [[ "$CHECK_MODE" == "true" ]]; then
        log_info "[check] kubectl -n argocd patch application $app (operation.sync)"
        return 0
    fi
    # Finding D v1.2 (THE cause of "namespaces cert-manager not
    # found", and a LATENT bug across the 17 previous runs): a manual
    # sync fired with an EMPTY `operation.sync` **does not inherit
    # spec.syncPolicy.syncOptions**. Live evidence (ArgoCD v3.4.3):
    # specOpts=[ServerSideApply,CreateNamespace] but opOpts=null, and
    # the Namespace does NOT appear in the syncResult — the task of
    # creating it never got in. Up to now it worked on the rebound:
    # the AUTO-sync (which does use the spec's options) created the ns
    # minutes before our manual sync arrived. On bringing cert-manager
    # forward (the fix for Finding A) we arrived first and the chart
    # was applied against a namespace that did not exist. Worse:
    # ArgoCD then marks "failed previous sync attempt ... will not
    # retry" and the auto-sync STOPS retrying that revision — the
    # manual failure poisons the automatic recovery.
    # Fix: the manual sync carries the spec's options EXPLICITLY.
    local sync_patch='{"operation":{"sync":{}}}' spec_opts
    spec_opts="$(kubectl -n argocd get application "$app" \
        -o jsonpath='{.spec.syncPolicy.syncOptions}' 2>/dev/null || true)"
    if [[ "$spec_opts" == \[*\] ]]; then
        sync_patch="{\"operation\":{\"sync\":{\"syncOptions\":$spec_opts}}}"
        log_info "sync $app: the spec's options propagated to the operation ($spec_opts)"
    fi
    local patch_out="" patch_rc=0 sync_noop=false
    patch_out="$(kubectl -n argocd patch application "$app" --type merge \
        -p "$sync_patch" 2>&1)" || patch_rc=$?
    if (( patch_rc != 0 )); then
        local inflight
        inflight="$(kubectl -n argocd get application "$app" \
            -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)"
        if [[ "$inflight" == "Running" ]]; then
            log_warn "sync $app: selfHeal operation IN FLIGHT — I adopt it and wait for its terminal phase"
            prev_started=""
        else
            printf '%s\n' "$patch_out" >&2
            _gate_record "sync-$app" fail 0
            return 1
        fi
    elif grep -q 'no change' <<< "$patch_out"; then
        sync_noop=true
        log_warn "sync $app: NO-OP patch ('no change' — residual .operation, H5) — the present state is accepted if it is already the desired one"
    fi
    local waited=0 phase started t0=$SECONDS net_refires=0 val_refires=0 wh_refires=0
    local live_sync live_health
    while :; do
        started="$(kubectl -n argocd get application "$app" \
            -o jsonpath='{.status.operationState.startedAt}' 2>/dev/null || true)"
        phase="$(kubectl -n argocd get application "$app" \
            -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)"
        # H5(i): no new operation is possible — a no-op declared by
        # the patch, or 30s with no change of startedAt — the verdict
        # comes out of the STATE: Synced + Healthy + last operation
        # Succeeded = what the sync was after already exists → gate
        # PASS:
        if [[ "$sync_noop" == "true" ]] \
           || { (( waited >= 30 )) && [[ -n "$prev_started" && "$started" == "$prev_started" ]]; }; then
            if [[ "$phase" == "Succeeded" ]]; then
                live_sync="$(kubectl -n argocd get application "$app" \
                    -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
                live_health="$(kubectl -n argocd get application "$app" \
                    -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
                if [[ "$live_sync" == "Synced" && "$live_health" == "Healthy" ]]; then
                    log_ok "sync $app: no new operation, but the desired state ALREADY exists (Synced+Healthy+Succeeded) — H5 #15"
                    _gate_record "sync-$app" pass $(( SECONDS - t0 ))
                    return 0
                fi
            fi
        fi
        if [[ -z "$prev_started" || "$started" != "$prev_started" ]]; then
            case "$phase" in
                Succeeded) break ;;
                Failed|Error)
                    local op_msg
                    op_msg="$(kubectl -n argocd get application "$app" \
                        -o jsonpath='{.status.operationState.message}' 2>/dev/null || true)"
                    # F-A/F-D run #15: with errexit ALIVE (the
                    # orchestrator's fix) a network transient here
                    # would kill the phase — if the failure has a
                    # NETWORK signature (the DNS "server misbehaving"
                    # of the phone took the sync down live), the sync
                    # is RE-FIRED and the wait continues inside the
                    # timeout. A CAP of 5 re-fires (P1.11): the
                    # network signature is broad ("connection refused"
                    # may be a badly configured service) — persistent
                    # ≠ transient, and past the cap it is reported as
                    # a REAL failure with the msg:
                    if grep -qiE "$AEGIS_NET_SIGS" <<< "$op_msg" \
                       && (( waited < timeout && net_refires < 5 )); then
                        net_refires=$(( net_refires + 1 ))
                        log_warn "sync $app: $phase from a transient NETWORK fault — re-fire $net_refires/5 (${waited}s/${timeout}s)"
                        prev_started="$started"
                        run_cmd kubectl -n argocd patch application "$app" \
                            --type merge -p "$sync_patch" || true
                        sleep 5; waited=$(( waited + 5 ))
                        continue
                    fi
                    # is the CAUSE in the per-resource detail? The
                    # App's message is the generic SYMPTOM ("tasks
                    # are not valid"); the real reason lives in
                    # syncResult.resources[].message (A v1.1):
                    local res_msgs
                    res_msgs="$(kubectl -n argocd get application "$app" -o json 2>/dev/null \
                        | jq -r '[.status.operationState.syncResult.resources[]?.message // empty] | join(" ")' 2>/dev/null || true)"
                    # Finding A v1.1 — A WEBHOOK THAT DOES NOT SERVE:
                    # the provider (cert-manager, kyverno) is halfway
                    # up. It takes 1-2 min from cold: LONG retries
                    # (30/60/90/120/150s ≈ 7 min of ceiling), with a
                    # counter of its own:
                    if grep -qiE "$AEGIS_WEBHOOK_NOTREADY_SIGS" <<< "$op_msg $res_msgs" \
                       && (( wh_refires < 5 )); then
                        wh_refires=$(( wh_refires + 1 ))
                        local wh_wait=$(( wh_refires * 30 ))
                        log_warn "sync $app: the ADMISSION WEBHOOK that governs these resources is not serving yet (A v1.1) — retry $wh_refires/5 in ${wh_wait}s (a provider from cold takes 1-2 min)"
                        printf '  cause: %s\n' "$(grep -oiE "$AEGIS_WEBHOOK_NOTREADY_SIGS[^\"]*" <<< "$op_msg $res_msgs" | head -1)" >&2
                        prev_started="$started"
                        sleep "$wh_wait"; waited=$(( waited + wh_wait ))
                        run_cmd kubectl -n argocd patch application "$app" \
                            --type merge -p "$sync_patch" || true
                        sleep 5; waited=$(( waited + 5 ))
                        continue
                    fi
                    # Finding A v1.0: "tasks are not valid" on the
                    # first sync = a discovery/generator that has not
                    # converged yet — a KNOWN transient. Retry with
                    # backoff (3 times, ~10-15s: the one in the real
                    # run validated fine seconds later). Its OWN
                    # counter: it does not share a cap with the
                    # network ones:
                    if grep -qiE "$AEGIS_SYNC_VALIDATION_SIGS" <<< "$op_msg" \
                       && (( waited < timeout && val_refires < 3 )); then
                        val_refires=$(( val_refires + 1 ))
                        log_warn "sync $app: $phase from a transient VALIDATION fault (discovery without the types yet? — Finding A v1.0) — retry $val_refires/3 in $(( 5 * val_refires + 5 ))s"
                        prev_started="$started"
                        sleep $(( 5 * val_refires + 5 ))
                        waited=$(( waited + 5 * val_refires + 5 ))
                        run_cmd kubectl -n argocd patch application "$app" \
                            --type merge -p "$sync_patch" || true
                        sleep 5; waited=$(( waited + 5 ))
                        continue
                    fi
                    printf '%s\n' "$op_msg" >&2
                    # when dying FOR REAL: WHICH task is invalid, not
                    # just the generic phrase (Finding A, explicitly
                    # requested) — the syncResult's resources with a
                    # message + the App's conditions:
                    log_error "sync $app ended $phase — detail of tasks/resources:"
                    kubectl -n argocd get application "$app" -o json 2>/dev/null \
                        | jq -r '(.status.operationState.syncResult.resources[]? | select((.status? // "") != "Synced" or ((.message? // "") | test("error|invalid|failed"; "i"))) | "  \(.kind)/\(.name): \(.status // "-") — \(.message // "-")"),
                                 (.status.conditions[]? | "  cond \(.type): \(.message)")' >&2 || true
                    (( net_refires >= 5 )) && \
                        log_error "sync $app: 5 re-fires with the SAME network signature — this is no longer transient (a badly configured service behind the signature?)"
                    (( val_refires >= 3 )) && \
                        log_error "sync $app: 3 validation retries exhausted — the types/resources above do NOT converge on their own: a broken manifest, or a genuinely absent CRD"
                    _gate_record "sync-$app" fail $(( SECONDS - t0 ))
                    return 1 ;;
            esac
        fi
        if (( waited >= timeout )); then
            log_error "sync $app with no NEW terminal phase in ${timeout}s (phase=${phase:-?})"
            # H7 bonus: a previous op Succeeded + a timeout waiting
            # for something "new" with the App sustainedly OutOfSync =
            # DRIFT (defaulting/mutation), NOT timing — say it with
            # the resources, do not leave the reader to work it out:
            if [[ "$phase" == "Succeeded" ]]; then
                log_error "op=Succeeded at the moment of the timeout — if the App is sustainedly OutOfSync this is DRIFT (admission defaulting, H7), not timing; non-Synced resources:"
                kubectl -n argocd get application "$app" -o json 2>/dev/null \
                    | jq -r '.status.resources[]? | select(.status != "Synced") | "  \(.kind)/\(.name): \(.status)"' >&2 || true
            fi
            _gate_record "sync-$app" fail $(( SECONDS - t0 ))
            return 1
        fi
        # H5(ii): periodic evidence — 17 minutes of silence was the
        # mute-timeout anti-pattern, once again, in the helper that
        # most phases use:
        if (( waited > 0 && waited % 30 == 0 )); then
            log_info "sync $app: waiting for a new operation (${waited}s/${timeout}s) — phase=${phase:-?} startedAt=${started:-?}"
        fi
        sleep 5; waited=$(( waited + 5 ))
    done
    # its OWN wait for Healthy (replaces the mute kubectl wait):
    # evidence every 30s, and when it runs out it prints the unhealthy
    # resources + the pods and events of the DESTINATION namespace —
    # the evidence that solved H6 at a glance (ImagePullBackOff
    # visible instantly):
    local hwaited=0 health
    while :; do
        health="$(kubectl -n argocd get application "$app" \
            -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
        if [[ "$health" == "Healthy" ]]; then
            # class G of the audit: pass AND fail both land in gates.jsonl:
            _gate_record "sync-$app" pass $(( SECONDS - t0 ))
            return 0
        fi
        if (( hwaited >= timeout )); then
            log_error "sync $app: no Healthy in ${timeout}s (health=${health:-?}) — unhealthy resources:"
            kubectl -n argocd get application "$app" -o json 2>/dev/null \
                | jq -r '.status.resources[]? | select((.health.status // "Healthy") != "Healthy" or .status != "Synced") | "  \(.kind)/\(.name): sync=\(.status) health=\(.health.status // "-") \(.health.message // "")"' >&2 || true
            local dest_ns
            dest_ns="$(kubectl -n argocd get application "$app" \
                -o jsonpath='{.spec.destination.namespace}' 2>/dev/null || true)"
            if [[ -n "$dest_ns" ]]; then
                kubectl -n "$dest_ns" get pods >&2 || true
                kubectl -n "$dest_ns" get events --sort-by=.lastTimestamp \
                    2>/dev/null | tail -n 10 >&2 || true
            fi
            _gate_record "sync-$app" fail $(( SECONDS - t0 ))
            return 1
        fi
        if (( hwaited > 0 && hwaited % 30 == 0 )); then
            log_info "sync $app: waiting for Healthy (${hwaited}s/${timeout}s, health=${health:-?})"
        fi
        sleep 5; hwaited=$(( hwaited + 5 ))
    done
}

# ── reinforced gate for Apps of (almost) only Secrets ───────────────
# Run #4: for a KSOPS App, "Healthy" is TRIVIAL (Secrets have no
# health) — the sync may have failed the whole build and the wait for
# Healthy passes all the same. This gate: (1) tells a BROKEN build
# (kustomize ComparisonError) apart from a TRANSIENT network
# ComparisonError (git fetch down — run #8: jenkins-secrets "broken
# build" that passed on the retry; with the operator's mobile network
# it is frequent), and both apart from pure timing; (2) demands Synced
# FOR REAL, with a generous poll (timing pattern #8).
# F-B run #15: the jenkins-secrets sync died from a transient DNS
# fault and this gate PASSED all the same — the App was "Synced"… TO
# THE OLD REVISION. "Synced" on its own does not prove that what was
# just pushed is applied. A third parameter: the expected sha
# (rev-parse HEAD after the push) — Synced only counts if
# revision/revisions contains it (ArgoCD automated retries on its own
# refresh cycle, so the poll converges):
argo_secrets_gate() {   # <app> [timeout_s] [expected_sha]
    local app="$1" timeout="${2:-300}" expected="${3:-}" waited=0
    local cond msg t0=$SECONDS
    while :; do
        cond="$(kubectl -n argocd get application "$app" \
            -o jsonpath='{.status.conditions[*].type}' 2>/dev/null || true)"
        if grep -q 'ComparisonError' <<< "$cond"; then
            msg="$(kubectl -n argocd get application "$app" \
                -o jsonpath='{.status.conditions[*].message}' 2>/dev/null || true)"
            if grep -qiE 'dial tcp|i/o timeout|lookup|failed to get git|connection refused|connection reset|EOF' <<< "$msg"; then
                log_warn "$app: TRANSIENT network ComparisonError — waiting (${waited}s/${timeout}s)"
                # E-1 of the in-VM report #14: the environment's DNS
                # gets dirty intermittently and the init did not tell
                # it apart from a bug. At 60s of sustained transient,
                # runbook §1.9 gets printed as a HINT (diagnosis, not
                # automatic remediation — restarting CoreDNS is the
                # operator's call):
                if (( waited == 60 )); then
                    log_warn "60s of sustained transient error — DNS runbook (§1.9): on the host 'ip route' + 'resolvectl status' (a phantom route/nameserver?); if the CLUSTER does not resolve: 'kubectl -n kube-system rollout restart deploy/coredns'"
                fi
            else
                printf '%s\n' "$msg" >&2
                _gate_record "$app-synced" fail $(( SECONDS - t0 ))
                die "$app: kustomize build BROKEN (an entry/resource with no file? — the generator's temporal rule)"
            fi
        elif kubectl -n argocd get application "$app" \
               -o jsonpath='{.status.sync.status}' 2>/dev/null | grep -qx Synced; then
            if [[ -n "$expected" ]]; then
                local revs
                revs="$(kubectl -n argocd get application "$app" \
                    -o jsonpath='{.status.sync.revision} {.status.sync.revisions}' \
                    2>/dev/null || true)"
                if ! grep -q "$expected" <<< "$revs"; then
                    # the if form (not `(( )) &&`): with errexit ALIVE
                    # (F-A) a statement that returns 1 kills the phase:
                    if (( waited % 30 == 0 )); then
                        log_warn "$app: Synced, but to an OLD revision — waiting for ${expected:0:8} (${waited}s/${timeout}s)"
                    fi
                    sleep 5; waited=$(( waited + 5 ))
                    if (( waited >= timeout )); then
                        printf 'live revision: %s / expected: %s\n' "$revs" "$expected" >&2
                        _gate_record "$app-synced" fail $(( SECONDS - t0 ))
                        die "GATE $app-synced FAILED — it never reached the pushed revision (F-B #15)"
                    fi
                    continue
                fi
            fi
            _gate_record "$app-synced" pass $(( SECONDS - t0 ))
            log_ok "GATE $app-synced"
            return 0
        fi
        if (( waited >= timeout )); then
            # H7 run #13: the error of the retried apply lives in
            # operationState and the timeout died MUTE — show it:
            kubectl -n argocd get application "$app" \
                -o jsonpath='{.status.operationState.message}' >&2 || true
            echo >&2
            # H7 run #15: op Succeeded + sustained OutOfSync = ALWAYS
            # drift (admission defaulting — Kyverno injects fields on
            # admission), not timing. Say it with the guilty resources
            # instead of leaving the deduction to the log's reader:
            local end_phase
            end_phase="$(kubectl -n argocd get application "$app" \
                -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)"
            if [[ "$end_phase" == "Succeeded" ]]; then
                log_error "op=Succeeded and still not Synced: this is DRIFT (admission defaulting/mutation — H7 #15), not timing. Non-Synced resources (review the App's ignoreDifferences):"
                kubectl -n argocd get application "$app" -o json 2>/dev/null \
                    | jq -r '.status.resources[]? | select(.status != "Synced") | "  \(.kind)/\(.name): \(.status)"' >&2 || true
            fi
            _gate_record "$app-synced" fail $(( SECONDS - t0 ))
            die "GATE $app-synced FAILED — it did not converge in ${timeout}s (above: operationState.message and diagnosis)"
        fi
        # H5(ii) #15: the "not Synced yet, no error" path was this
        # gate's only MUTE one — periodic evidence:
        if (( waited > 0 && waited % 30 == 0 )); then
            log_info "$app: waiting for Synced (${waited}s/${timeout}s)"
        fi
        sleep 5; waited=$(( waited + 5 ))
    done
}

# ── ansible: become with no friction and no timeout ─────────────────
# Run #4: --ask-become-pass per playbook = TWO prompts in phase 20 and
# "Timed out waiting for become success" if the operator takes too long.
#
# Run #6, BUG 1 — the --become-password-file fallback was NOT honoured
# live: the detector fell correctly onto the file path, the operator
# typed the password, and BOTH playbooks died with "Timed out waiting
# for become success or become password prompt" — ansible ignored the
# file and waited for an interactive prompt. The flag had been
# "verified against the source of ansible-core 2.21" but NOT tested
# live: the same verified-against-source ≠ tested class as CF's
# permission groups. The binary decided, not the source. It was
# unblocked with NOPASSWD.
#
# DECISION: do NOT retry the untested flag. When there is NO NOPASSWD,
# the init ROUTES onto the ONLY path tested live — it installs a
# NOPASSWD drop-in (validated with visudo, a RED brake, reversible
# with rm) and runs ansible non-interactively. The password goes ONLY
# to sudo -S's stdin (never argv, never a persistent file).
# ANSIBLE_BECOME_ARGS is left empty on purpose: become escalates
# through NOPASSWD, not through a flag.
# OPEN DEBT (VALIDACION §4.x): reproduce why ansible-core ignores
# --become-password-file in this setup (local conn + become). It is
# NOT claimed as solved — it is worked around with the tested path.
# Usage:  ansible_become_setup
#         ansible-playbook ... "${ANSIBLE_BECOME_ARGS[@]}"
declare -a ANSIBLE_BECOME_ARGS=()
ansible_become_setup() {
    ANSIBLE_BECOME_ARGS=()
    # sudo -K FIRST (run #5, finding 0): `sudo -n true` gives a FALSE
    # POSITIVE if there is a cached timestamp from an earlier sudo
    # (phase 05 leaves it primed) — the init believed NOPASSWD,
    # ansible (another session, no cache) asked for the password and
    # died on a timeout. -K kills the cache: -n only passes with REAL
    # NOPASSWD in sudoers:
    sudo -K 2>/dev/null || true
    if sudo -n true 2>/dev/null; then
        log_info "sudo with no password (real NOPASSWD, cache purged) — non-interactive become"
        return 0
    fi
    : "${SECRETS_TMP:?ansible_become_setup requires secrets_workdir first}"
    # P0.4 of the audit: in --non-interactive there is nobody to ask
    # for the password — and this was discovered ~30 min into a run.
    # Phase 00's doctor already detects it early; this die is the
    # final net:
    ni_mode && die "sudo without NOPASSWD in --non-interactive — install the drop-in BEFORE running: printf '%s ALL=(ALL) NOPASSWD:ALL\\n' \"\$(id -un)\" | sudo tee /etc/sudoers.d/010-aegis-init-nopasswd && sudo chmod 0440 /etc/sudoers.d/010-aegis-init-nopasswd"
    log_warn "sudo without NOPASSWD — NOPASSWD is going to be enabled for the user (become's by-file fallback did NOT work in run #6; NOPASSWD is the only tested path)"
    gate_red "enable sudo NOPASSWD for $(id -un) on THIS host (a drop-in in /etc/sudoers.d — reversible: 'sudo rm /etc/sudoers.d/010-aegis-init-nopasswd'). On a DISPOSABLE greenfield VM this is what is expected; if this is a REAL host, ABORT and configure sudoers by hand"
    local _pw f_dropin
    read -rsp "sudo password (ONCE; it goes only to sudo's stdin, never to argv nor to a file): " _pw \
        || die "stdin closed asking for the sudo password — configure NOPASSWD and --non-interactive"
    echo >&2
    f_dropin="$SECRETS_TMP/aegis-nopasswd"
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$(id -un)" > "$f_dropin"
    chmod 0440 "$f_dropin"
    # validate the syntax BEFORE installing (a broken sudoers breaks
    # sudo); this sudo -S is ALSO the password's self-test: if it is
    # wrong it dies HERE in seconds, not on a 60s timeout halfway
    # through the playbook:
    if ! printf '%s' "$_pw" | sudo -S -k -p '' visudo -cf "$f_dropin" >/dev/null 2>&1; then
        unset _pw
        die "sudo -S failed (wrong password?) or the drop-in does not validate — /etc/sudoers.d intact"
    fi
    printf '%s' "$_pw" | sudo -S -k -p '' install -m 0440 -o root -g root \
        "$f_dropin" /etc/sudoers.d/010-aegis-init-nopasswd \
        || { unset _pw; die "could not install the NOPASSWD drop-in in /etc/sudoers.d"; }
    unset _pw
    # the tmpfs copy was left 0440 and the cleanup's shred could not
    # overwrite it ("Permission denied", cosmetic, seen in #15) — the
    # one installed in /etc/sudoers.d keeps its own 0440:
    chmod u+w "$f_dropin" 2>/dev/null || true
    sudo -K 2>/dev/null || true
    gate "nopasswd-activo" bash -c "sudo -n true 2>/dev/null"
    log_ok "NOPASSWD active — ansible runs non-interactively along the tested path (become with no flag)"
}

# ── dual git state of the platform repo (CR-6 in-VM report #14) ─────
# $PLATFORM_DIR is a working clone that the init mutates and pushes —
# but NOTHING guaranteed it was up to date when a phase started. The
# REAL flow of #14: the operator fixes something by hand on GitHub (or
# in another clone) → resumes the init → this clone was left BEHIND →
# the next push overwrites the fix or collides. Every phase that
# mutates the repo STARTS by synchronising: ff-only brings in what is
# remote; if it diverged (local commits not pushed AND new remote ones
# at the same time) the init does NOT decide on its own — it dies with
# the state in plain sight so that the operator can reconcile:
platform_repo_sync() {
    if ! git -C "$PLATFORM_DIR" rev-parse --abbrev-ref '@{upstream}' \
         >/dev/null 2>&1; then
        log_info "platform with no upstream yet (pre-phase-12) — sync skipped"
        return 0
    fi
    run_cmd retry_net 3 git -C "$PLATFORM_DIR" fetch origin || \
        die "platform fetch failed — network or deploy key; re-run the phase"
    if run_cmd git -C "$PLATFORM_DIR" merge --ff-only '@{upstream}'; then
        log_info "platform up to date with the remote (ff-only)"
        return 0
    fi
    git -C "$PLATFORM_DIR" status -sb >&2 || true
    git -C "$PLATFORM_DIR" log --oneline -3 '@{upstream}' >&2 || true
    # P3 of the audit: "DIVERGED" was also the diagnosis when the
    # merge failed because of a DIRTY WORKING TREE (a previous phase
    # dead halfway, before the commit) — a different remedy, a
    # different message:
    if [[ -n "$(git -C "$PLATFORM_DIR" status --porcelain 2>/dev/null)" ]]; then
        die "the merge failed with a DIRTY working tree (above: status) — a previous phase died between mutating and committing; review the changes in $PLATFORM_DIR (commit or discard them) and re-run the phase"
    fi
    die "the platform clone DIVERGED from the remote (local AND remote commits at once) — reconcile by hand in $PLATFORM_DIR and re-run the phase"
}

# ── commit ONLY if there are changes (class F, audit 2026-07-18) ────
# `git commit || true` lived in 6 phases: the || true existed for the
# re-run with no changes, but it also swallowed the REAL failures
# (hook, identity, index.lock) → the "successful" push carried nothing
# and ArgoCD never saw the change (the symptom appeared 2 phases
# later). The right distinction is STRUCTURAL: an empty staged area =
# a legitimate no-op; a staged area with changes = the commit MUST
# come out fine (errexit kills it if it does not). Usage:
# git_commit_if_changes <dir> <msg> [paths-to-add...]
# (no paths = add -A).
git_commit_if_changes() {
    local dir="$1" msg="$2"; shift 2
    if (($#)); then
        run_cmd git -C "$dir" add -- "$@"
    else
        run_cmd git -C "$dir" add -A
    fi
    if git -C "$dir" diff --cached --quiet; then
        log_info "nothing to commit (idempotent re-run)"
        return 0
    fi
    run_cmd git -C "$dir" commit -m "$msg" --no-verify
}

# ── git push ALWAYS verified (run #9) ───────────────────────────────
# A failed push that "carries on regardless" leaves a local commit
# unpushed → ArgoCD does not see the file → kustomize broken ONE PHASE
# later (the kustomize error is the symptom; the cause is the
# unverified push). retry_net absorbs the transient cut of the mobile
# network; if it fails anyway, die with the REAL cause and the phase
# to resume from:
git_push_verified() {   # <repo_dir> [extra push args...]
    local dir="$1"; shift
    run_cmd retry_net 3 git -C "$dir" push "$@" || \
        die "git push failed in $dir — a local commit NOT pushed (ArgoCD would read an old repo); check the network/deploy key and re-run the phase"
}

# ── rollouts TOLERANT of a slow network (phases 20/40 — E-1) ────────
# The operator's signature phrase: "the 20/40 falls over, I re-run it
# without changing anything and it works". Cause: the first boot pulls
# images from docker.io over the mobile network and a `rollout status
# --timeout=120s` turns SLOW into FAILED — the re-run "works" only
# because the pull carried on in the background and ended up cached.
# With a mobile network, a transient ImagePullBackOff is NORMAL (the
# kubelet retries with backoff by itself). A GENEROUS wait + periodic
# evidence: slow is never mute, and the final timeout dies with the
# real state:
wait_rollout() {   # <ns> <kind/name> [timeout_s=900] [every_s=20]
    local ns="$1" obj="$2" timeout="${3:-900}" every="${4:-20}" waited=0
    until kubectl -n "$ns" rollout status "$obj" --timeout=5s \
            >/dev/null 2>&1; do
        if (( waited >= timeout )); then
            log_error "rollout $ns/$obj did not converge in ${timeout}s — real state:"
            kubectl -n "$ns" get pods >&2 || true
            kubectl -n "$ns" get events --sort-by=.lastTimestamp \
                2>/dev/null | tail -n 8 >&2 || true
            return 1
        fi
        local notready
        notready="$(kubectl -n "$ns" get pods --no-headers 2>/dev/null \
                    | grep -vE 'Running|Completed' | head -n 3 || true)"
        log_info "waiting for $ns/$obj (${waited}s/${timeout}s)${notready:+ — $(echo "$notready" | tr '\n' ' ')}"
        sleep "$every"; waited=$(( waited + every ))
    done
}

# ── CONVERGENCE BEFORE MEASURING (the init's nº1 family) ────────────
# Five instances of the SAME bug in five disguises: a coredns that
# does not exist (H4), a sync operation that never arrives (H5), an
# old Succeeded read as new (bug C), a sync against a discovery
# without the types (A v1.0), a gate measuring in the middle of a
# cascade of ReplicaSets (B v1.0). The rule, canonised here:
#   EXISTENCE → STABILITY → only then MEASURE.
# Every gate that measures the effect of an asynchronous action goes
# through these helpers — a new one-off patch of this class = a review
# FAIL, not a run failure.

# wait_for <timeout_s> <every_s> <what-I-am-waiting-for> <cmd...>
#   The primitive: a poll with periodic EVIDENCE (every ~30s it says
#   what it is waiting for) and a timeout that names what did not
#   arrive. For one-off conditions; for workloads use k8s_converged.
wait_for() {
    local timeout="$1" every="$2" what="$3"; shift 3
    local t0=$SECONDS last_log=0
    until "$@"; do
        if (( SECONDS - t0 >= timeout )); then
            log_error "waiting for '$what': it did not arrive in ${timeout}s"
            return 1
        fi
        if (( SECONDS - t0 - last_log >= 30 )); then
            last_log=$(( SECONDS - t0 ))
            log_info "waiting for '$what' ($(( SECONDS - t0 ))s/${timeout}s)"
        fi
        sleep "$every"
    done
}

# k8s_converged <ns> <kind/name> [timeout=300]
#   EXISTENCE (the object may not be created yet — H4/A) → STABILITY
#   (rollout status: observed generation + replicas up to date — B: a
#   restart plus Kyverno's mutation chain TWO deployments and in that
#   window 3+ ReplicaSets coexist). The caller measures AFTER this
#   returns 0.
k8s_converged() {
    local ns="$1" obj="$2" timeout="${3:-300}"
    # bash -c: the redirection belongs TO THE PROBE, not to wait_for
    # (otherwise it would swallow the helper's own periodic evidence):
    wait_for "$timeout" 3 "existence of $ns/$obj" \
        bash -c "kubectl -n '$ns' get '$obj' -o name >/dev/null 2>&1" || return 1
    wait_rollout "$ns" "$obj" "$timeout"
}

# deploy_current_pods_ok <ns> <deploy> <jq-filter-per-pod>
#   Measures ONLY the pods of the deployment's CURRENT ReplicaSet (by
#   the pod-template-hash of the RS with the highest revision and
#   replicas>0) — in a cascade of deployments "the namespace's pods"
#   ALWAYS include old pods on their way out (B v1.0). It demands >=1
#   pod and that ALL of the current RS' pods satisfy the jq filter
#   (over the pod object):
deploy_current_pods_ok() {
    local ns="$1" deploy="$2" jqf="$3" hash
    hash="$(kubectl -n "$ns" get rs -o json 2>/dev/null | jq -r --arg d "$deploy" '
        [.items[] | select((.metadata.ownerReferences[]? | select(.kind=="Deployment" and .name==$d)) != null)
                  | select((.spec.replicas // 0) > 0)]
        | max_by(.metadata.annotations["deployment.kubernetes.io/revision"] | tonumber)
        | .metadata.labels["pod-template-hash"] // empty')"
    [[ -n "$hash" ]] || { log_error "no current ReplicaSet for $ns/$deploy"; return 1; }
    kubectl -n "$ns" get pods -l "pod-template-hash=$hash" -o json 2>/dev/null \
        | jq -e "[.items[] | select(.metadata.deletionTimestamp == null)] | length > 0 and all(${jqf})" >/dev/null
}

# webhook_serving <ns> <svc> [timeout=300]
#   Finding A v1.1 — instance nº6 of the family, and the most
#   deceptive one: an App that PROVIDES an admission webhook is
#   "Synced + Healthy" BEFORE its webhook serves. In that window,
#   every apply of a resource governed by that webhook dies with
#   "failed calling webhook ...: no endpoints available for service" —
#   and the error is NOT the resource's, it is the provider's, halfway
#   up.
#   The REAL signal is neither the App's health nor the deployment's
#   rollout: it is the Service's ENDPOINTS (a non-empty addresses =
#   there are ready pods behind it). THAT is what is waited for before
#   syncing any App that creates resources of that domain:
webhook_serving() {   # <ns> <svc> [timeout]
    local ns="$1" svc="$2" timeout="${3:-300}"
    wait_for "$timeout" 3 "existence of the Service $ns/$svc (webhook)" \
        bash -c "kubectl -n '$ns' get svc '$svc' -o name >/dev/null 2>&1" || return 1
    if ! wait_for "$timeout" 3 "ENDPOINTS of the webhook $ns/$svc (the App's Healthy is NOT enough)" \
        bash -c "[[ -n \"\$(kubectl -n '$ns' get endpoints '$svc' -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)\" ]]"; then
        log_error "the webhook $ns/$svc has no endpoints — pods of the ns:"
        kubectl -n "$ns" get pods >&2 || true
        return 1
    fi
    log_ok "webhook $ns/$svc SERVING (endpoints present)"
}

# ── probes with kubectl run: reset BEFORE each attempt ──────────────
# P1.8 of the audit: `kubectl run --rm` + retry ANNULS ITSELF — if the
# attach times out (slow network), the pod stays alive and ALL the
# retries die with AlreadyExists, in exactly the scenario the retry
# exists for. Every retryable probe deletes its pod first:
probe_reset() {   # <ns> <pod-name>
    kubectl -n "$1" delete pod "$2" --ignore-not-found --now \
        >/dev/null 2>&1 || true
}

# ── signatures of a transient NETWORK error (E-1, one place) ────────
# They are consumed by argo_sync (which re-fires the sync),
# argo_secrets_gate (which waits instead of dying) and
# jenkins_build_retry (which re-fires the build). "server misbehaving"
# = the upstream DNS of the operator's phone, seen LIVE in #15 taking
# down the sync and (probably) the build:
AEGIS_NET_SIGS='dial tcp|i/o timeout|TLS handshake timeout|server misbehaving|connection reset|connection refused|temporary failure|could not resolve|unexpected EOF|lookup .* on|failed to get git'

# signatures of a transient VALIDATION failure of a sync (Finding A
# v1.0): the first sync after creating/updating the root App may run
# against an API server discovery that has not registered the types
# the App applies yet (the root was deploying CRDs 12s earlier), or
# against a half-materialised generator → "one or more synchronization
# tasks are not valid" / "no matches for kind". Same input, 4 min
# later: Synced in 7s. It is the convergence family (instance #4):
AEGIS_SYNC_VALIDATION_SIGS='tasks are not valid|not valid|no matches for kind|could not find the requested resource|conversion webhook.* (failed|denied|unavailable)|failed to sync cluster.*cache'

# signatures of a WEBHOOK THAT IS NOT SERVING YET (Finding A v1.1, the
# REAL text from the run): "failed calling webhook
# webhook.cert-manager.io: no endpoints available for service
# cert-manager-webhook". The App's message above said "tasks are not
# valid" (which matched), but the per-resource detail —the one that
# says the CAUSE— matched no signature at all: it was being classified
# by the symptom, not by the cause. And the timing matters: a webhook
# provider from cold takes 1-2 min, so THIS class carries LONGER
# retries than the rest (the 3×10s of the previous session was
# insufficient — said by the operator, with evidence):
AEGIS_WEBHOOK_NOTREADY_SIGS='failed calling webhook|no endpoints available|webhook.*(connection refused|context deadline exceeded)|x509.*webhook'

# ── network vs config ───────────────────────────────────────────────
# retry_net: gates with egress retry before diagnosing (the
# network-vs-config lesson: rule out a network cut first).
retry_net() {
    local tries="$1"; shift
    # P1.11 of the audit: a fixed 3×5s = 15s in total against mobile
    # network cuts that last MINUTES — the retry existed but did not
    # cover the real cut. Capped exponential backoff (5/15/45/90/90…):
    # with tries=3 it covers ~1 min; with tries=6, ~5.5 min. The delay
    # is logged so that the wait is never mute:
    local i delay=5
    for ((i = 1; i <= tries; i++)); do
        "$@" && return 0
        (( i == tries )) && break
        # H4 run #15 (UX): the fixed "(network?)" mislabelled errors
        # that were NOT network ones (a NotFound from a creation race)
        # — the wrapper does not see the command's stderr, so it does
        # not ASSERT the cause: it points at the error above and hands
        # over the map:
        log_warn "attempt $i/$tries failed — retrying in ${delay}s (the cause is in the error ABOVE: timeout/DNS=transient network; NotFound=creation race; anything else=probably real)"
        sleep "$delay"
        delay=$(( delay * 3 )); (( delay > 90 )) && delay=90
    done
    return 1
}

# ══ the CLI: invoking another command, and the help ═════════════════
# (03 §1/§2/§5 — the two functions that were missing in v2)

# aegis_exec <command> [args...] — rule 5.1 made into a function.
#
# The bug that justifies it has a line and a date: aegis-check:766,785
# invoked aegis-edge and aegis-webhook by relative path, and the `case`
# that classified the output had no branch for 127. With the command
# absent —renamed, moved, without permissions— the round did not say
# «I could not look»: it said «no failures». Green through blindness is
# the worst outcome a surveillance tool can produce, because nobody
# investigates a green.
#
# Here 126 and 127 are rc 2 WITH the reason, never 0 and never 1.
aegis_exec() {
    local cmd="$1"; shift
    local target="$AEGIS_ROOT/libexec/aegis-$cmd"
    if [[ ! -e "$target" ]]; then
        printf 'COULD NOT EVALUATE: the command %s does not exist (%s) — it is not that there are no failures: it is that it could not be looked at\n' \
            "${AEGIS_CMD:-aegis} $cmd" "$target" >&2
        return 2
    fi
    if [[ ! -x "$target" ]]; then
        printf 'COULD NOT EVALUATE: %s exists but is not executable (chmod +x)\n' "$target" >&2
        return 2
    fi
    "$target" "$@"
    local rc=$?
    if [[ $rc == 126 || $rc == 127 ]]; then
        printf 'COULD NOT EVALUATE: %s could not be executed (rc %s: is the shebang interpreter missing?)\n' \
            "${AEGIS_CMD:-aegis} $cmd" "$rc" >&2
        return 2
    fi
    return $rc
}

# cli_help — prints the `# aegis-help:` block of the calling file,
# plus the table of exit codes. The table is NOT written here: it
# lives in share/exit-codes.txt and lib/aegis/
# outcomes.py reads it too, so that bash and python cannot disagree
# about what a 2 means.
cli_help() {
    local file="${1:-${BASH_SOURCE[1]}}"
    sed -n '/^# aegis-help:/,/^[^#]/p' "$file" | sed '1d;$d;s/^# \?//'
    echo
    cat "$AEGIS_ROOT/share/exit-codes.txt"
}
