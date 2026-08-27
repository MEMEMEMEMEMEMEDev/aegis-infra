#!/usr/bin/env bash
# PHASE 85 — observability (fase-85.md, executed; design in
# observability/design.md). WHY 85: by the time it runs, EVERYTHING it
# is going to observe already exists (the registry with TLS, Jenkins
# with builds, Kyverno in Enforce, the tunnel alive) — an observability
# phase placed before the things it observes would only have trivial
# gates, and a gate that cannot fail measures nothing.
#
# THE EDGE (02 §3.2). Everything this phase does about the OUTSIDE has
# two shapes and only one of them is Cloudflare: the derivation of
# public_hostnames and the tunnel's apply (85.6), grafana's Access
# application (85.2), cloudflared's metrics hook (85.7) and its
# convergence (85.10). Under EDGE=local none of the four has a subject,
# and each one says so where it used to run instead of quietly not
# being there. What does NOT change is everything that measures the
# inside — which is almost all of it — and the gate this phase exists
# for: the heartbeat reaching the topic, over whichever public path
# this instance has.
#
# Internal order = §6 of the plan, 12 steps: bring from the seed →
# render → secrets → AppProjects → edge → hooks → root →
# producers-before-consumers → re-sync of the observed →
# ingestion of the history → gates. Idempotent for `--only 85` over a
# live instance: gen_or_restore reuses credentials, the copies/entries
# have a STRUCTURAL guard (never a grep of a mention — H4), the render
# is a no-op with no live placeholders, argo_sync is idempotent, and
# the ingestion re-uploads gates.jsonl (duplicates in vlogs-events:
# accepted — it is the history of bootstraps, deduplicated at query
# time by ts+gate; a "I have already ingested up to here" state would
# be more mechanism than the problem — §9).
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
# ── WHICH EDGE this instance has (02 §3.2) ─────────────────────────
# The local edge is not another init: it is another VALUE of the conf.
# Everything below branches on THIS variable and nothing asks "which
# profile am I". A conf written before 2026-08-26 does not carry it and
# can only be cloudflare — the same default config_validate applies.
EDGE="${EDGE:-cloudflare}"

# ── a gate whose SUBJECT does not exist under this edge ─────────────
# The doctrine of the house, and the reason this is a function and not a
# mute `if`: a step that does not apply SAYS SO, with the whole reason.
# The three outcomes of a measurement are done / already there / COULD
# NOT EVALUATE, and this is the third one — a NOTICE, never an approval.
# "I did not look" and "it is fine" are two different facts and they
# used to give one single signal.
# It keeps the gate's NAME in gates.jsonl with a result that is neither
# pass nor fail: a gate that simply stops being written VANISHES from
# the record, and three months later a missing line reads exactly like a
# green one. That is Disease E with the lights off — and the ingestion
# of 85.11 carries these lines to vlogs-events like all the others, so
# the history says which gates this edge never had a subject for.


# CR-6 in-VM report #14: this phase MUTATES the platform repo — the
# local clone may be behind the remote. Synchronize FIRST:
platform_repo_sync
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/aegis.key}"

# argo_sync comes from lib/common.sh (bug C run #8) — never a local
# definition.

PLATFORM_SEED="$AEGIS_ROOT/seed/platform"
B="$PLATFORM_DIR/k8s/base"
OBS="$B/observability"
TOFU="$PLATFORM_DIR/tofu/tofu-apply.sh"
TUNNEL_ENV="$PLATFORM_DIR/tofu/envs/cloudflare-tunnel"

# ── 85.2 BRING FROM THE SEED whatever the instance lacks ────────
# RUTA.md's rule ("it comes in through seed/+init/ or it did not come
# in") applied to the live-instance case, where phase 10 does NOT
# re-seed (platform/ with .git is the truth). On a virgin start all of
# this is a no-op: the seed already brings it.
#
# (a) NEW files: copy them verbatim if missing.
if [[ ! -d "$OBS" ]]; then
    run_cmd cp -a "$PLATFORM_SEED/k8s/base/observability" "$OBS"
    log_ok "k8s/base/observability/ copied from the seed (a live instance without observability)"
fi
APPS_OBS="$PLATFORM_DIR/k8s/argocd-apps/observability.yaml"
if [[ ! -f "$APPS_OBS" ]]; then
    run_cmd cp -a "$PLATFORM_SEED/k8s/argocd-apps/observability.yaml" "$APPS_OBS"
    log_ok "argocd-apps/observability.yaml copied from the seed"
fi
# grafana.tf: a NEW file and not an edit of main.tf ON PURPOSE
# (fase-85 §5): HCL merges every .tf in the directory — a new file is
# copied verbatim into a live instance without merge surgery.
#
# CLOUDFLARE ONLY, and the reason is not that the file is unused: an
# Access application is a product OF THE ZONE. With no zone there is no
# application, no service token and no door to put in front of grafana.
# What local loses here is worth naming: under cloudflare grafana is
# published on the internet with Access as the door and its own login as
# the second lock; under local grafana is reachable only through the
# host bridge on EDGE_BIND_IP, and its login is the ONLY lock there is.
# The address the bridge listens on IS the whole perimeter.
GRTF="$PLATFORM_DIR/tofu/modules/cloudflare-access/grafana.tf"
# ${EDGE:-cloudflare} and NOT "$EDGE": every phase runs in its own
# subshell (`( source "$p" )`), so the default config_validate applies
# does not survive phase 00. With a conf written before EDGE existed the
# variable is simply absent, and under `set -u` a bare "$EDGE" does not
# fall back to cloudflare — it kills the phase with «unbound variable».
# A conf with no EDGE is a cloudflare conf, which is the only thing it
# could ever have been.
if [[ "${EDGE:-cloudflare}" == cloudflare ]]; then
    if [[ ! -f "$GRTF" ]]; then
        if [[ -f "$PLATFORM_SEED/tofu/modules/cloudflare-access/grafana.tf" ]]; then
            run_cmd cp -a "$PLATFORM_SEED/tofu/modules/cloudflare-access/grafana.tf" "$GRTF"
            log_ok "cloudflare-access/grafana.tf copied from the seed"
        else
            # fase-85 §12: grafana's Access App is a B4 deliverable.
            # Fail-closed and LOUD: continuing without it would publish
            # grafana.<dom> with its login as the only lock.
            die "tofu/modules/cloudflare-access/grafana.tf is missing (in seed and instance) — a B4 prerequisite (fase-85 §5/§12): without grafana's Access App the hostname is NOT exposed; finish B4 and re-run the phase"
        fi
    fi
else
    log_warn "EDGE=local: there is no Cloudflare Access application for grafana — with no zone there is nothing to put in front of it. grafana answers only through the host bridge on ${EDGE_BIND_IP:-127.0.0.1} and its own login is the ONLY lock: whoever reaches that address reaches the login"
fi

# (b) entries guarded inside EXISTING files — a STRUCTURAL guard
# (yaml_lists_file: a real list entry, never a grep of a mention — H4)
# and a write that VALIDATES the resulting YAML BEFORE touching the
# file (the inject_placeholder pattern — fase-85 §9: if it does not
# parse, the file is left intact).
_yaml_insert_after() {   # <yaml> <anchor-regex> <line-to-insert>
    python3 - "$1" "$2" "$3" <<'EOF'
import re, sys, yaml
p, anchor, line = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(p).read()
lines = text.splitlines()
hits = [i for i, l in enumerate(lines)
        if re.search(anchor, l) and not l.lstrip().startswith("#")]
if len(hits) != 1:
    sys.exit(f"_yaml_insert_after: anchor {anchor!r} with {len(hits)} non-comment "
             f"occurrences in {p} (EXACTLY 1 is required)")
lines.insert(hits[0] + 1, line)
out = "\n".join(lines) + ("\n" if text.endswith("\n") else "")
try:
    list(yaml.safe_load_all(out))
except Exception as e:
    sys.exit(f"_yaml_insert_after: the resulting YAML of {p} does NOT parse ({e}) "
             f"— the file is left INTACT")
open(p, "w").write(out)
EOF
}

# sourceRepos ×3 in the aegis-platform AppProject (enumerated, NOT '*'
# — they must match the exact repoURL of observability.yaml):
APPPROJ="$PLATFORM_DIR/k8s/bootstrap/appprojects.yaml"
for _repo in 'https://victoriametrics.github.io/helm-charts' \
             'https://helm.vector.dev' \
             'https://grafana.github.io/helm-charts'; do
    yaml_lists_file "$APPPROJ" "$_repo" || \
        run_cmd _yaml_insert_after "$APPPROJ" \
            '^\s*-\s*https://kyverno\.github\.io/kyverno\s*$' \
            "    - $_repo"
done
_sourcerepos_ok() {
    yaml_lists_file "$APPPROJ" 'https://victoriametrics.github.io/helm-charts' && \
    yaml_lists_file "$APPPROJ" 'https://helm.vector.dev' && \
    yaml_lists_file "$APPPROJ" 'https://grafana.github.io/helm-charts'
}
gate "obs-sourcerepos-en-appproject" _sourcerepos_ok

# grafana and ntfy under `platform:` in edge.yaml — the list from
# which `aegis org edge` DERIVES public_hostnames (nobody edits
# main.tf by hand; the lesson of ai.__ROOT_DOMAIN__).
# The DECLARATION is written under both edges on purpose: edge.yaml
# says what the edge has to expose, and under local those two doors
# exist just the same (traefik serves them, the host bridge hands them
# over). What has no subject under local is the DERIVATION into the
# tunnel's main.tf — that is guarded in 85.6, not here.
EDGE_YAML="$PLATFORM_DIR/edge.yaml"
yaml_lists_file "$EDGE_YAML" grafana || \
    run_cmd _yaml_insert_after "$EDGE_YAML" '^  - jenkins$' '  - grafana'
yaml_lists_file "$EDGE_YAML" ntfy || \
    run_cmd _yaml_insert_after "$EDGE_YAML" '^  - grafana$' '  - ntfy'
_edge_hostnames_ok() {
    yaml_lists_file "$EDGE_YAML" grafana && yaml_lists_file "$EDGE_YAML" ntfy
}
gate "obs-edge-declara-grafana-ntfy" _edge_hostnames_ok

# ── 85.3 render of the config-class placeholders ───────────────────
# Idempotent; it renders the __OBS_*__/__AEGIS_PROFILE__ of the
# just-copied files (fase-85 §4.3 — the derivation table per $PROFILE
# lives next to render_platform_placeholders in common.sh).
# On a virgin start phase 10 already did it and this is a no-op.
render_platform_placeholders

# ── 85.4 SECRETS (§3, the same path as everything else: A7/D11) ────
secrets_workdir

# grafana_admin_pass → grafana-admin.enc.yaml (keys admin-user /
# admin-password: the chart's contract with admin.existingSecret).
# Grafana sits behind Access BUT keeps its login: Access is the door,
# not the only lock (fase-85 §3).
GRAF_PASS="$(gen_or_restore grafana_admin_pass gen_password_b64)"
GRAF_USER="$(materialize grafana-admin-user admin)"
make_enc_secret grafana-admin observability \
    "$OBS/grafana-admin.enc.yaml" \
    "admin-user=$GRAF_USER" "admin-password=$GRAF_PASS"

# ntfy_bridge_token → ntfy-bridge-token.enc.yaml: the WHOLE scfg
# config of ntfy-alertmanager (key `config`) — it carries the
# credential the bridge PUBLISHES to ntfy with, which is why it lives
# in a Secret and not in a ConfigMap (contract documented in
# ntfy-bridge.yaml):
BRIDGE_PASS="$(gen_or_restore ntfy_bridge_token gen_password_b64)"
{
    printf 'http-address :8080\n'
    printf 'alert-mode single\n'
    printf 'ntfy {\n'
    printf '    server http://ntfy.observability.svc\n'
    printf '    topic aegis-alertas\n'
    printf '    user puente\n'
    printf '    password %s\n' "$(cat "$BRIDGE_PASS")"
    printf '}\n'
    printf 'cache {\n'
    printf '    type memory\n'
    printf '}\n'
} > "$SECRETS_TMP/ntfy-bridge.scfg"
make_enc_secret ntfy-bridge-token observability \
    "$OBS/ntfy-bridge-token.enc.yaml" \
    "config=$SECRETS_TMP/ntfy-bridge.scfg"

# ntfy_operador_pass: the phone app's credential. It does NOT go into
# a K8s Secret (nobody in the cluster consumes it — the same reasoning
# as access_st in phase 25): it lives in the store and is shown to the
# operator ONCE (a human_step further down, once ntfy is already
# alive). The restore/persist pair goes LITERAL and not through
# gen_or_restore because we need to know whether it is NEW (only then
# is it shown):
NTFY_OP_RC=0
OPF="$(restore_secret ntfy_operador_pass)" || NTFY_OP_RC=$?
store_rc_guard "$NTFY_OP_RC" ntfy_operador_pass
NTFY_OPERATOR_NEW=false
if (( NTFY_OP_RC != 0 )); then
    OPF="$(gen_password_b64 ntfy_operador_pass)"
    persist_secret ntfy_operador_pass "$OPF"
    NTFY_OPERATOR_NEW=true
fi

# the generator entries IN THE SAME COMMIT as the .enc.yaml (temporal
# rule, run #4). The seed already brings them as a REAL list entry;
# the structural guard + gate cover a diverged instance:
GEN_OBS="$OBS/secret-generator.yaml"
yaml_lists_file "$GEN_OBS" grafana-admin.enc.yaml || \
    run_cmd _yaml_insert_after "$GEN_OBS" '^files:$' '  - grafana-admin.enc.yaml'
gate "obs-grafana-admin-en-generator" \
    yaml_lists_file "$GEN_OBS" grafana-admin.enc.yaml
yaml_lists_file "$GEN_OBS" ntfy-bridge-token.enc.yaml || \
    run_cmd _yaml_insert_after "$GEN_OBS" '^files:$' '  - ntfy-bridge-token.enc.yaml'
gate "obs-ntfy-bridge-en-generator" \
    yaml_lists_file "$GEN_OBS" ntfy-bridge-token.enc.yaml

# ── ntfy's bcrypt hashes (GENERATED-class, owner: this phase) ──────
# ntfy's auth-users wants `user:bcrypt-hash:role` in the ConfigMap.
# The hash is derived with htpasswd -B: already a hard dependency of
# the init (derive_htpasswd_and_regcreds, phase 40; declared in
# lib/checks.sh) — no python3-bcrypt, nothing new. -C 10 matches the
# cost ntfy itself uses (`ntfy user hash`); htpasswd's $2y$ is
# accepted by the Go bcrypt that ntfy uses (the same combination
# documented for traefik).
# The password NEVER through argv: htpasswd -i reads it from stdin
# (A27).
_ntfy_hash() {   # <passfile> → a bcrypt hash on stdout (and nothing else)
    htpasswd -nBi -C 10 x < "$1" | cut -d: -f2 | tr -d '\n'
}
# does the LIVE hash in the yaml match the store's password?
# (convergence guard: a re-run with no changes = a no-op; a ROTATED
# password = the old hash no longer verifies and is replaced — without
# this, aegis-rotate's rotation recipe would be a silent no-op):
NTFY_YAML="$OBS/ntfy.yaml"
_ntfy_hash_up_to_date() {   # <user> <passfile>
    # anchored to the `:user"` role of auth-users — without that, the
    # `user:topic:permission` entry of auth-access matches too (the
    # fixtures harness caught it before any instance was touched):
    local h
    h="$(grep -oP -- "-\s*\"$1:\K[^:\"]+(?=:user\")" "$NTFY_YAML" | head -1)"
    [[ -n "$h" && "$h" != __OBS_* ]] || return 1
    printf '%s:%s\n' "$1" "$h" > "$SECRETS_TMP/htcheck-$1"
    htpasswd -vi "$SECRETS_TMP/htcheck-$1" "$1" < "$2" >/dev/null 2>&1
}
_ntfy_hash_replace() {   # <user> <hashfile> — rotation: overwrite the old hash
    python3 - "$NTFY_YAML" "$1" "$2" <<'EOF'
import re, sys, yaml
p, user, hpath = sys.argv[1], sys.argv[2], sys.argv[3]
h = open(hpath).read().strip()
text = open(p).read()
# anchored to the `:user"` role of auth-users: the auth-access entry
# (`user:topic:permission`) also starts the same way and must NOT be
# touched:
pat = re.compile(r'(- "%s:)[^:"]+(:user")' % re.escape(user))
out, n = pat.subn(lambda m: m.group(1) + h + m.group(2), text)
if n != 1:
    sys.exit(f"hash of {user}: {n} occurrences (EXACTLY 1 is required) in {p}")
try:
    list(yaml.safe_load_all(out))
except Exception as e:
    sys.exit(f"the resulting YAML of {p} does NOT parse ({e}) — it is left INTACT")
open(p, "w").write(out)
EOF
}
NTFY_CONF_CHANGED=false
_ntfy_user_converged() {   # <user> <passfile> <placeholder>
    local user="$1" passfile="$2" ph="$3"
    if placeholder_pending "$NTFY_YAML" "$ph"; then
        _ntfy_hash "$passfile" > "$SECRETS_TMP/hash-$user"
        run_cmd inject_placeholder "$NTFY_YAML" "$ph" "$SECRETS_TMP/hash-$user"
        NTFY_CONF_CHANGED=true
    elif ! _ntfy_hash_up_to_date "$user" "$passfile"; then
        log_warn "the hash of '$user' in ntfy.yaml does NOT match the store's password (a rotation?) — it is re-derived and replaced"
        _ntfy_hash "$passfile" > "$SECRETS_TMP/hash-$user"
        run_cmd _ntfy_hash_replace "$user" "$SECRETS_TMP/hash-$user"
        NTFY_CONF_CHANGED=true
    fi
}
_ntfy_user_converged operador "$OPF"         __OBS_NTFY_OPERADOR_HASH__
_ntfy_user_converged puente   "$BRIDGE_PASS" __OBS_NTFY_PUENTE_HASH__
# a gate on the RESULT (the H4 family's rule): the live hash VERIFIES
# against the store's password — not merely "the placeholder died":
gate "obs-ntfy-hash-operador" _ntfy_hash_up_to_date operador "$OPF"
gate "obs-ntfy-hash-puente"   _ntfy_hash_up_to_date puente "$BRIDGE_PASS"

# ── __OBS_CA_PEM__: the LIVE CA into blackbox's ConfigMap ──────────
# The same pattern as __AEGIS_CA_PEM__ in phase 80 (the CA does not
# exist until cert-manager issues it in phase 35). blackbox validates
# the chain AGAINST this CA — never insecure_skip_verify (the -k that
# P2.4 banished): a probe with -k would give the same expiry but would
# let a WRONG cert through in green.
CAY="$OBS/configmap-aegis-ca.yaml"
# The live CA, in a file. It had ONE reader (the injection right
# below) and under EDGE=local it grows a second one at the end of the
# phase: there, the gates go out through hostnames that traefik serves
# with the wildcard certificate of THIS CA, and no stock trust store
# knows it. Extracted so both readers ask for the SAME file and
# neither re-derives it (idempotent: on a re-run the placeholder is
# already dead and the file has not been written yet):
_obs_ca_pem() {   # -> $SECRETS_TMP/obs-aegis-ca.pem, or non-zero
    [[ -s "$SECRETS_TMP/obs-aegis-ca.pem" ]] && return 0
    kubectl -n cert-manager get secret aegis-internal-ca \
        -o jsonpath='{.data.ca\.crt}' | base64 -d \
        > "$SECRETS_TMP/obs-aegis-ca.pem"
    [[ -s "$SECRETS_TMP/obs-aegis-ca.pem" ]]
}
OBS_CA_REINJECTED=false
# (if the live CA cannot be read, the placeholder branch below dies
#  with the reason; here it only means there is nothing to compare)
if _obs_ca_pem && ! placeholder_pending "$CAY" __OBS_CA_PEM__ \
   && pem_stale "$CAY" "$SECRETS_TMP/obs-aegis-ca.pem"; then
    # presence is not identity (re-init over a previous instance): the
    # ConfigMap carries a dead cluster's CA; blackbox would trust the
    # wrong chain and every registry probe would fail in red
    log_warn "blackbox's CA ConfigMap carries a CA that is NOT the live one — re-injecting and restarting blackbox"
    run_cmd reinject_pem "$CAY" "$SECRETS_TMP/obs-aegis-ca.pem"
    OBS_CA_REINJECTED=true
fi
if placeholder_pending "$CAY" __OBS_CA_PEM__; then
    _obs_ca_pem || die "the live CA could not be read from cert-manager/aegis-internal-ca — blackbox validates the registry's chain AGAINST it (phase 35 is the one that issues it)"
    run_cmd inject_placeholder "$CAY" __OBS_CA_PEM__ "$SECRETS_TMP/obs-aegis-ca.pem"
fi
gate "obs-ca-inyectado" bash -c \
    "grep -q 'BEGIN CERTIFICATE' '$CAY' && ! grep -q '__OBS_CA_PEM__' '$CAY'"

# commit + push: ArgoCD reads from the remote, not from the disk. No
# || true (class F): an empty staged set = a legitimate no-op, a real
# failure kills it here.
git_commit_if_changes "$PLATFORM_DIR" \
    "feat(observability): apps + encrypted secrets + CA and hashes injected"
git_push_verified "$PLATFORM_DIR"

# ── 85.5 AppProjects via kubectl (class C1, as in phase 35) ────────
# Without the new sourceRepos, a chart's first sync would die with
# "not permitted". Imperative bootstrap infrastructure, outside root:
run_cmd kubectl apply -f "$PLATFORM_DIR/k8s/bootstrap/appprojects.yaml"
gate "obs-sourcerepos-aplicados" bash -c \
  "kubectl -n argocd get appproject aegis-platform -o json \
     | jq -e '.spec.sourceRepos | contains([\"https://victoriametrics.github.io/helm-charts\",\"https://helm.vector.dev\",\"https://grafana.github.io/helm-charts\"])' >/dev/null"

# ── 85.6 the edge: DERIVED hostnames + tofu apply ──────────────────
# `aegis org edge` derives public_hostnames from edge.yaml + the
# contracts (nobody edits main.tf by hand); the apply creates the
# CNAMEs, the tunnel's ingress and grafana's Access App (grafana.tf).
# The RESULT gate is the two edge gates of §8 at the end; here only
# the derivation is verified (cheap, and with a clear cause if
# edge.yaml diverged).
#
# CORRECTED on 2026-08-24 — this line was dead in TWO ways at once and
# would have killed the phase at step 85.6:
#
#   1. it invoked `bin/aegis-org` inside $PLATFORM_DIR, and the code no
#      longer lives in the instance. It moved to the PRODUCT (02 §1),
#      and check 134 now enforces that the seed carries no executables
#      at all — so that path cannot exist by construction;
#   2. the subcommand was renamed `borde` -> `edge` when the CLI surface
#      went English (docs/cli/design.md §4).
#
# Either one alone was fatal. Together they are the C3 finding already
# logged in plan/06 §91 and docs/cli/inconsistencies.md — logged, and
# still live in the code until now. It is the same class the whole of
# v3 is ordered around: a caller that names a thing by where it USED to
# be. The dispatcher is on PATH from phase 05, so the invocation no
# longer needs a directory at all — which is what makes it stop being
# breakable this way.
#
# ALL FOUR THINGS THIS BLOCK DOES BELONG TO CLOUDFLARE: it derives
# public_hostnames into the TUNNEL's main.tf, creates the CNAMEs in the
# zone, adds the two hostnames to the tunnel's ingress and mints
# grafana's Access application. Under EDGE=local not one of them has a
# subject — there is no zone to write a record into, no tunnel to route
# through and no Access to protect anything with. And nothing needs to
# be derived for the two doors to exist: the names resolve through
# sslip.io to EDGE_BIND_IP and land on the host bridge, which has been
# listening since phase 25, and traefik already carries their
# IngressRoutes.
# WHAT IS LOST: those two hostnames stop being reachable from the
# internet and stop being covered by Access. That is the trade of this
# edge, not an oversight of this phase.
if [[ "${EDGE:-cloudflare}" == cloudflare ]]; then
    run_cmd "${AEGIS_CMD:-aegis}" org edge
    gate "obs-borde-derivado" bash -c \
      "grep -E 'public_hostnames *= *\[' '$TUNNEL_ENV/main.tf' | grep -q '\"grafana\"' \
       && grep -E 'public_hostnames *= *\[' '$TUNNEL_ENV/main.tf' | grep -q '\"ntfy\"'"
    run_cmd "$TOFU" -chdir="$TUNNEL_ENV" apply -auto-approve || \
        die "the edge's tofu apply FAILED — a partial apply leaves the CNAMEs/ingress poisoned; review the plan by hand and re-run the phase"
    # the tfstate at 600 as soon as it is written (phase 25 / fix #82 —
    # the .backup was left 664 with the tunnel's token IN THE CLEAR):
    for f in "$TUNNEL_ENV"/terraform.tfstate "$TUNNEL_ENV"/terraform.tfstate.backup; do
        [[ -f "$f" ]] && chmod 600 "$f"
    done
    # The enc.json re-encrypted POST-apply is committed HERE and not
    # later: the wrapper warns «COMMIT IT» and it is right — without this
    # commit the good state is left orphaned in the working tree, the next
    # platform_repo_sync dies over a dirty tree, and sooner or later
    # somebody discards it and the edge's truth GOES BACKWARDS
    # (2026-08-21: three applies measuring against an enc.json 9 days
    # old).
    git_commit_if_changes "$PLATFORM_DIR" \
        "chore(edge): tunnel state re-encrypted post-apply (phase 85)" \
        tofu/envs/cloudflare-tunnel/terraform.tfstate.enc.json
else
    gate_no_subject "obs-borde-derivado" \
        "EDGE=local: there is no zone to derive public_hostnames into and no tunnel ingress to add them to — grafana.$ROOT_DOMAIN and ntfy.$ROOT_DOMAIN resolve through sslip.io to the host bridge on ${EDGE_BIND_IP:-127.0.0.1}, which routes them with no derivation at all. No tofu state is written here either, so there is nothing to re-encrypt and nothing to commit"
fi

# ── 85.7 ≤3-line HOOKS in the observed (hooks.md / §7) ─────────────
# In the seed they ship from the factory; here they are added to the
# live instance with a STRUCTURAL guard (parse the YAML, not a grep of
# a mention) and a write that validates the result before touching the
# file. On a fresh instance: a no-op.

# (1) cloudflared: --metrics 0.0.0.0:2000 + containerPort.
CFD="$B/ingress/cloudflare-tunnel/cloudflared.yaml"
_cloudflared_metrics_ok() {
    python3 - "$CFD" <<'EOF'
import sys, yaml
for d in yaml.safe_load_all(open(sys.argv[1])):
    if d and d.get("kind") == "Deployment":
        for c in d["spec"]["template"]["spec"]["containers"]:
            if c.get("name") == "cloudflared" and "--metrics" in (c.get("args") or []):
                sys.exit(0)
sys.exit(1)
EOF
}
_hook_up_cloudflared() {
    python3 - "$CFD" <<'EOF'
import sys, yaml
p = sys.argv[1]
text = open(p).read()
old = 'args: ["tunnel", "--no-autoupdate", "run"]'
new = ('args: ["tunnel", "--no-autoupdate", "--metrics", "0.0.0.0:2000", "run"]\n'
       '          ports:\n'
       '            - {name: metrics, containerPort: 2000}')
if text.count(old) != 1:
    sys.exit(f"cloudflared.yaml: {text.count(old)} occurrences of the expected args "
             f"(1 is required) — the file diverged, hook it up by hand (fase-85 §7)")
out = text.replace(old, new)
try:
    list(yaml.safe_load_all(out))
except Exception as e:
    sys.exit(f"the resulting YAML does NOT parse ({e}) — {p} is left INTACT")
open(p, "w").write(out)
EOF
}
# CLOUDFLARE ONLY, and this is the one that costs the most to lose.
# With EDGE=local there is no cloudflared Deployment to hook up, so
# vmagent's `cloudflared` job discovers nothing, the two rules of the
# cloudflared family (TunelSinConexion / TunelSinScrape) have no series
# to look at, and the «edge» dashboard renders empty. THE ALERT DOES
# NOT DISAPPEAR: it stays committed and stays loaded, and TunelSinScrape
# —absent() over a metric nobody produces— fires 30 minutes after the
# switch-on and every day afterwards. It is said here, out loud,
# because a stack that cries wolf from birth is the same disease as one
# that stays mute: by the third day nobody reads it. Making that family
# know about the edge does NOT live in this phase — the rules and the
# scrape job are seed manifests, identical under both edges — and it is
# reported as a change owed by another file.
if [[ "${EDGE:-cloudflare}" == cloudflare ]]; then
    _cloudflared_metrics_ok || run_cmd _hook_up_cloudflared
    gate "obs-enchufe-cloudflared" _cloudflared_metrics_ok
else
    gate_no_subject "obs-enchufe-cloudflared" \
        "EDGE=local: there is no cloudflared Deployment to add --metrics to — the tunnel does not exist on this edge, and its scrape job, its two alerts and the edge panel go with it"
fi

# (2) Jenkins: the `prometheus` plugin in installPlugins (it exposes
# /prometheus without an API key; plain `metrics` demands a key via a
# query param — hostile to scraping. hooks.md):
JVALS="$B/platform/jenkins/values.yaml"
yaml_lists_file "$JVALS" prometheus || \
    run_cmd _yaml_insert_after "$JVALS" '^    - job-dsl$' '    - prometheus'
gate "obs-enchufe-jenkins-plugin" yaml_lists_file "$JVALS" prometheus

# (3) registry: a debug block with prometheus in the ConfigMap + port
# 5001 in the Service (a debug listener SEPARATE from the public one):
REGY="$B/registry-system/registry.yaml"
_registry_metrics_ok() {
    python3 - "$REGY" <<'EOF'
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
cfg = next((d for d in docs if d.get("kind") == "ConfigMap"
            and d["metadata"]["name"] == "registry-config"), None)
svc = next((d for d in docs if d.get("kind") == "Service"
            and d["metadata"]["name"] == "registry"), None)
ok = False
if cfg:
    inner = yaml.safe_load(cfg["data"]["config.yml"])
    ok = bool(((inner.get("http") or {}).get("debug") or {})
              .get("prometheus", {}).get("enabled"))
ok = ok and svc is not None and \
     any(p.get("port") == 5001 for p in svc["spec"]["ports"])
sys.exit(0 if ok else 1)
EOF
}
_hook_up_registry() {
    python3 - "$REGY" <<'EOF'
import sys, yaml
p = sys.argv[1]
text = open(p).read()
v_cfg = ("      tls:\n"
         "        certificate: /certs/tls.crt\n"
         "        key: /certs/tls.key\n")
n_cfg = v_cfg + ("      debug:\n"
                 "        addr: :5001\n"
                 "        prometheus: {enabled: true}\n")
v_svc = "  ports: [{port: 5000, targetPort: 5000}]"
n_svc = ("  ports:\n"
         "    - {name: registry, port: 5000, targetPort: 5000}\n"
         "    - {name: metrics, port: 5001, targetPort: 5001}")
if text.count(v_cfg) != 1 or text.count(v_svc) != 1:
    sys.exit(f"registry.yaml does not have the expected shape for the hook "
             f"(cfg={text.count(v_cfg)} svc={text.count(v_svc)}, 1 and 1 are required) "
             f"— the file diverged, hook it up by hand (fase-85 §7)")
out = text.replace(v_cfg, n_cfg).replace(v_svc, n_svc)
try:
    list(yaml.safe_load_all(out))
except Exception as e:
    sys.exit(f"the resulting YAML does NOT parse ({e}) — {p} is left INTACT")
open(p, "w").write(out)
EOF
}
REGISTRY_HOOKED_UP_THIS_RUN=false
if ! _registry_metrics_ok; then
    run_cmd _hook_up_registry
    # class D (the golden rule): config of a live pod ⇒ restart or
    # checksum. The new ConfigMap does NOT restart the registry on its
    # own — it is noted for the rollout restart after the re-sync
    # (85.10):
    REGISTRY_HOOKED_UP_THIS_RUN=true
fi
gate "obs-enchufe-registry" _registry_metrics_ok

# (4) default-deny netpols that WOULD BLOCK the plumbing (one entry
# per file; without this, up==0 with everything "healthy" — a scrape
# hole indistinguishable from an incident, on the profile where holes
# are routine):
_netpol_allows_observability() {   # <netpol.yaml>
    python3 - "$1" <<'EOF'
import sys, yaml
for d in yaml.safe_load_all(open(sys.argv[1])):
    if not d:
        continue
    for r in (d.get("spec", {}).get("ingress") or []):
        for f in (r.get("from") or []):
            sel = (f.get("namespaceSelector") or {}).get("matchLabels") or {}
            if sel.get("kubernetes.io/metadata.name") == "observability":
                sys.exit(0)
sys.exit(1)
EOF
}
_netpol_open_to_observability() {   # <netpol.yaml> <port>...
    python3 - "$@" <<'EOF'
import sys, yaml
p, ports = sys.argv[1], sys.argv[2:]
text = open(p).read()
block = ['    - from:',
         '        - namespaceSelector:',
         '            matchLabels: {kubernetes.io/metadata.name: observability}',
         '      ports:'] + \
        ['        - {protocol: TCP, port: %s}' % pt for pt in ports]
out = text.rstrip("\n") + "\n" + "\n".join(block) + "\n"
try:
    docs = list(yaml.safe_load_all(out))
except Exception as e:
    sys.exit(f"the resulting YAML does NOT parse ({e}) — {p} is left INTACT")
# the effect, not the write: the append must have landed INSIDE the
# ingress list of a policy (if the file diverged and does not end in
# that list, better to die here than to leave a broken netpol live):
ok = any((f.get("namespaceSelector") or {}).get("matchLabels", {})
         .get("kubernetes.io/metadata.name") == "observability"
         for d in docs if d
         for r in (d.get("spec", {}).get("ingress") or [])
         for f in (r.get("from") or []))
if not ok:
    sys.exit(f"the append to {p} did not land inside ingress (diverged file?) — hook it up by hand")
open(p, "w").write(out)
EOF
}
NP_JENKINS="$B/platform/jenkins-secrets/netpol.yaml"
NP_ARGOCD="$B/platform/argocd-secrets/netpol.yaml"
NP_TRIVY="$B/trivy-system/netpol.yaml"
_netpol_allows_observability "$NP_JENKINS" || \
    run_cmd _netpol_open_to_observability "$NP_JENKINS" 8080
_netpol_allows_observability "$NP_ARGOCD" || \
    run_cmd _netpol_open_to_observability "$NP_ARGOCD" 8082 8083 8084
_netpol_allows_observability "$NP_TRIVY" || \
    run_cmd _netpol_open_to_observability "$NP_TRIVY" 4954
gate "obs-netpol-jenkins" _netpol_allows_observability "$NP_JENKINS"
gate "obs-netpol-argocd"  _netpol_allows_observability "$NP_ARGOCD"
gate "obs-netpol-trivy"   _netpol_allows_observability "$NP_TRIVY"

# commit of the hooks + the edge's re-encrypted tfstate (85.6) + push:
git_commit_if_changes "$PLATFORM_DIR" \
    "feat(observability): metrics hooks (cloudflared/jenkins/registry) + netpols + edge"
git_push_verified "$PLATFORM_DIR"

# ── 85.8 root MANUAL always (ADR-0012): the new Apps are born here ─
argo_sync root 300

# ── 85.9 syncs in ORDER: producers before consumers (D5) ───────────
# base first (namespace + Secrets + raw manifests: with no ns there is
# nowhere, with no Secret grafana does not start), then the stores,
# then the collectors, then vmalert, grafana last:
argo_sync observability-base 600
# a re-injected CA (re-init over a previous instance) lives in a
# ConfigMap blackbox already mounted: it needs a restart to trust the
# live chain (same subPath lesson as Kyverno's, phase 80)
if [[ "${OBS_CA_REINJECTED:-false}" == "true" ]]; then
    run_cmd kubectl -n observability rollout restart deploy/blackbox
    gate "obs-blackbox-con-ca-viva" wait_rollout observability deploy/blackbox 300
fi
# F-B #15: Synced counts ONLY for the JUST-pushed revision (the HEAD
# is the one from 85.7's push — nothing commits in between):
argo_secrets_gate observability-base 300 \
    "$(git -C "$PLATFORM_DIR" rev-parse HEAD)"
# A7: post-sync validation ALWAYS — Synced+Healthy does not guarantee
# the Secrets if the generator did not run:
gate "obs-secretos-vivos" poll 180 5 bash -c \
  "kubectl -n observability get secret grafana-admin ntfy-bridge-token >/dev/null 2>&1"
argo_sync vmsingle 600
argo_sync vlogs 600
argo_sync vlogs-events 600
argo_sync vmagent 600
argo_sync vector 600
argo_sync vmalert 600
argo_sync grafana 900

# ── 85.10 re-sync of the hooked-up observed ────────────────────────
# (the netpols we touched travel in their apps: jenkins-secrets /
#  argocd-secrets / trivy-system)
# The tunnel, again only under cloudflare: with EDGE=local there is no
# infra-edge/cloudflared to converge, and what hands the host over to
# traefik is the systemd bridge of phase 25 — which is not an App and
# does not sync from git.
if [[ "${EDGE:-cloudflare}" == cloudflare ]]; then
    argo_sync cloudflare-tunnel 600
    gate "obs-cloudflared-convergido" wait_rollout infra-edge deploy/cloudflared 600
else
    gate_no_subject "obs-cloudflared-convergido" \
        "EDGE=local: there is no cloudflared Deployment to converge — the host bridge hands ${EDGE_BIND_IP:-127.0.0.1}:80/443 to traefik's fixed ClusterIP and it was already listening before this phase ran"
fi
argo_sync jenkins-secrets
argo_sync argocd-secrets
argo_sync trivy-system
# jenkins' one RESTARTS the controller (a new plugin) — a one-time
# price; Jenkins' gate from phase 50 is not re-run, but convergence
# BEFORE measuring is (family #1):
argo_sync jenkins 900
gate "obs-jenkins-convergido" wait_rollout jenkins-system sts/jenkins 900
argo_sync registry 600
# Converge by EFFECT, not by history. The first version restarted only
# if the ConfigMap changed in THIS run
# ($REGISTRY_HOOKED_UP_THIS_RUN) — and the third boot-up (2026-08-21)
# found the hole: the hook had gone in on an EARLIER run, the pod had
# been carrying the old config for 12 days, the rollout the gate was
# waiting for never existed and wait_rollout passed over nothing —
# obs-metricas-fluyen died 15 minutes later pointing at registry:5001.
# It is B11 in the flesh: renewed config, stale pod. The honest
# condition: does the pod SERVE what the ConfigMap declares? Whether
# the change came from this run, from last week, or from a hand.
_registry_serves_metrics() {
    # Through the SERVICE and not through items[0] of the namespace
    # (check 72): the Service only routes to Ready pods, and during a
    # Recreate the [0] of the list could be the dying pod. If the Ready
    # pod does not listen on :5001, the curl to the Service fails all
    # the same — which is what this guard wants to know.
    local ip
    ip="$(kubectl -n registry-system get svc registry \
            -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
    [[ -n "$ip" && "$ip" != "None" ]] || return 1
    curl -fsS --max-time 5 "http://$ip:5001/metrics" >/dev/null 2>&1
}
if kubectl -n registry-system get cm registry-config -o jsonpath='{.data.config\.yml}' 2>/dev/null \
        | grep -q 'debug:' && ! _registry_serves_metrics; then
    log_info "the ConfigMap declares metrics and the pod does not serve them — rollout restart (B11)"
    run_cmd kubectl -n registry-system rollout restart deploy/registry
fi
gate "obs-registry-convergido" wait_rollout registry-system deploy/registry 600

# ── 85.11 ingestion of the init's history into vlogs-events ───────
# gates.jsonl (P2.13) → jsonline with _stream source=aegis-init. It is
# NOT best-effort: here the destination MUST exist — if it fails, the
# phase fails (unlike the per-gate push of hooks.md, which runs before
# the destination exists). The count is captured BEFORE: the gates
# below append new lines and the ≥ still holds.
GATES_JSONL="$AEGIS_STATE_DIR/gates.jsonl"
N_GATES=0
[[ -s "$GATES_JSONL" ]] && N_GATES="$(wc -l < "$GATES_JSONL")"
# An IP reachable from the HOST for a Service of the stack. The
# VictoriaMetrics/Logs charts create HEADLESS Services for their
# StatefulSets: a jsonpath of clusterIP returns the STRING "None",
# curl tries http://None:9428, and retry_net reads it as a network
# failure — that is how the boot-up of 2026-08-21 died, with 15 green
# gates above it. For a headless one we go to the first endpoint (the
# pod IP): on single-node k3s the pod IPs are routable from the host
# just like the ClusterIPs. Inside the cluster none of this applies
# (the headless DNS resolves on its own; the trivy-db-age CronJob uses
# the name and is fine as it is).
_svc_ip() {   # <svc> → a reachable IP, or empty (and the caller decides)
    local ip
    ip="$(kubectl -n observability get svc "$1" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
    if [[ -z "$ip" || "$ip" == "None" ]]; then
        ip="$(kubectl -n observability get endpoints "$1" \
                -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)"
    fi
    [[ -n "$ip" && "$ip" != "None" ]] && printf '%s' "$ip"
}
VLE_IP="$(_svc_ip vlogs-events)" \
    || die "vlogs-events has no reachable IP (a pod that is not Ready? kubectl -n observability get endpoints vlogs-events)"
_ingest_history() {
    # the source field is added with jq (byte-honest and without
    # depending on the server's extra_fields); the record's own ISO ts
    # = _time. The Content-Type is NOT decorative: without the header,
    # curl declares x-www-form-urlencoded and VictoriaLogs DISCARDS the
    # whole body with HTTP 200 and zero rows — no drop, no log, no
    # complaint (measured 2026-08-21 on the second boot-up: the request
    # counted, the bytes did not). The obs-eventos-ingestados gate
    # exists to catch exactly this class of false success, but better
    # not to feed it:
    jq -c '. + {source: "aegis-init"}' "$GATES_JSONL" \
      | curl -fsS --max-time 60 -H 'Content-Type: application/stream+json' \
          --data-binary @- \
          "http://$VLE_IP:9428/insert/jsonline?_time_field=ts&_msg_field=gate&_stream_fields=source"
}
if (( N_GATES > 0 )); then
    # Convergence of the re-run: the ingestion posts the WHOLE file,
    # and gates.jsonl is append-only — re-running the phase without
    # this guard would duplicate the ENTIRE history in the 1-year
    # store, one copy per run. If the stream already has at least as
    # many rows as the file, the history is already there (the ≥ and
    # not ==: this run's gates appended lines after the last
    # ingestion, and future runs will bring them):
    N_ALREADY="$(curl -fsS --max-time 20 "http://$VLE_IP:9428/select/logsql/query" \
              --data-urlencode 'query={source="aegis-init"} | stats count() as rows' 2>/dev/null \
            | jq -r '.rows // "0"' | head -n1)"
    [[ "$N_ALREADY" =~ ^[0-9]+$ ]] || N_ALREADY=0
    if (( N_ALREADY >= N_GATES )); then
        log_info "the history is already in vlogs-events ($N_ALREADY rows >= $N_GATES in the file): not re-ingesting"
    else
        run_cmd retry_net 3 _ingest_history || \
            die "ingestion of gates.jsonl into vlogs-events FAILED — the endpoint MUST exist (fase-85 §6.11); check the vlogs-events App"
        log_ok "history ingested: $N_GATES lines of gates.jsonl → vlogs-events (the history survives --reset-state)"
    fi
else
    log_warn "no gates.jsonl to ingest (a fresh --reset-state?) — what was ingested on previous runs SURVIVES in vlogs-events"
fi

# ── the trust of the gates that go out through the public path ─────
# Under EDGE=local the two hostnames of this phase (grafana and ntfy)
# are served by traefik with the wildcard certificate of aegis' OWN CA,
# which no stock trust store knows. Three of the gates below go out
# through them, and without this they would die on the handshake and
# report «unreachable» about a platform that is standing — a red that
# names the wrong thing costs almost as much as a false green.
# The CA is handed over EXPLICITLY and never with -k: a -k here would
# accept ANY certificate and the gate would stop measuring TLS at the
# exact moment it claims to measure it (the same -k that P2.4 banished
# from phase 40). Through the environment and not through a --cacert
# per call, because edge_origin_responds (lib/access.sh) builds its own
# curl and check 90 requires grafana to go through it: the trust
# belongs to the path, not to the call site.
# Under cloudflare NOTHING is exported: there those hostnames are
# served by Cloudflare with a public certificate, and the stock store
# is exactly the right one to validate it against.
if [[ "${EDGE:-cloudflare}" == local ]]; then
    _obs_ca_pem || die "EDGE=local: the CA could not be read from cert-manager/aegis-internal-ca, and the gates of grafana and ntfy go out over TLS issued by it — with no CA there is no honest way to validate the handshake"
    export CURL_CA_BUNDLE="$SECRETS_TMP/obs-aegis-ca.pem"
fi

# ── 85.12 FINAL GATES (§8): measure the EFFECT, not the deployment ─
VM_IP="$(_svc_ip vmsingle)"       || die "vmsingle has no reachable IP"
VLOGS_IP="$(_svc_ip vlogs)"       || die "vlogs has no reachable IP"
VMALERT_IP="$(_svc_ip vmalert)"   || die "vmalert has no reachable IP"
GRAFANA_IP="$(_svc_ip grafana)"   || die "grafana has no reachable IP"
_promql() {   # <query> → the value of the first result (or 0)
    curl -fsS --max-time 15 "http://$VM_IP:8428/api/v1/query" \
        --data-urlencode "query=$1" 2>/dev/null \
      | jq -r '.data.result[0].value[1] // "0"'
}
_logsql_count() {   # <ip> <LogsQL query with `stats count() as rows`>
    curl -fsS --max-time 20 "http://$1:9428/select/logsql/query" \
        --data-urlencode "query=$2" 2>/dev/null \
      | jq -r '.rows // "0"' | head -n1
}

# (1) obs-metricas-fluyen: vmagent is REALLY scraping. Expected floor:
# 13 static targets (vmagent + 8 of the stack + jenkins + registry +
# 2 blackbox probes) + cadvisor(1) + argocd(3) + cert-manager(1) +
# kyverno(≥1) + traefik(1) + cloudflared(1) ≈ 21; the floor is left at
# 18 (headroom for kyverno's variable replicas) AND on top of that
# zero up==0 — a target downed by a netpol is seen HERE and not 3 days
# later:
OBS_TARGETS_MIN=18
# One target fewer under EDGE=local: cloudflared does not exist, so its
# job discovers nothing. It does NOT show up as up==0 (a job with no
# discovered targets produces no series at all, which is precisely why
# JobDeScrapeDesaparecido counts jobs instead of reading values) — it
# shows up as one less in the count of up==1. A floor left at 18 would
# fail this gate for the one reason that is not a fault.
if [[ "${EDGE:-cloudflare}" == local ]]; then
    OBS_TARGETS_MIN=17
fi
_metrics_flowing() {
    local up_count down_count
    up_count="$(_promql 'count(up==1)')"
    down_count="$(_promql 'count(up==0)')"
    [[ "$up_count" =~ ^[0-9]+$ && "$down_count" =~ ^[0-9]+$ ]] || return 1
    (( up_count >= OBS_TARGETS_MIN )) || return 1
    (( down_count == 0 ))
}
_diag_up_down() {
    printf 'up==1: %s (expected >= %s); targets with up==0:\n' \
        "$(_promql 'count(up==1)')" "$OBS_TARGETS_MIN"
    curl -fsS --max-time 15 "http://$VM_IP:8428/api/v1/query" \
        --data-urlencode 'query=up==0' 2>/dev/null \
      | jq -r '.data.result[]?.metric | "  up==0: job=\(.job) instance=\(.instance)"'
}
gate_diag "obs-metricas-fluyen" '_diag_up_down' \
    poll 900 15 _metrics_flowing

# (2) obs-logs-fluyen: Vector → vlogs end to end (lines with a recent
# ts — Vector stamps its own timestamp, §9 WSL2 clock):
_logs_flowing() {
    local rows
    rows="$(_logsql_count "$VLOGS_IP" '_time:15m | stats count() as rows')"
    [[ "$rows" =~ ^[0-9]+$ ]] && (( rows > 0 ))
}
gate_diag "obs-logs-fluyen" \
    'kubectl -n observability get pods -l app.kubernetes.io/name=vector 2>/dev/null; kubectl -n observability logs daemonset/vector --tail=15 2>/dev/null' \
    poll 600 15 _logs_flowing

# (3) obs-eventos-ingestados: 85.11's ingestion LANDED (Synced does
# not prove data — the same lesson as F-B):
_events_ingested() {
    local rows
    rows="$(_logsql_count "$VLE_IP" '_stream:{source="aegis-init"} | stats count() as rows')"
    [[ "$rows" =~ ^[0-9]+$ ]] && (( rows >= N_GATES ))
}
gate_diag "obs-eventos-ingestados" \
    `# clase-E-ok: source=aegis-init is the LABEL of the VictoriaLogs stream (the logger sets it), not a command anyone types` \
    'printf "expected >= %s lines with _stream source=aegis-init\n" "$N_GATES"' \
    poll 300 10 _events_ingested

# (4) obs-cert-servido-medido: B11 FOR REAL — blackbox measures what
# the registry SERVES with a real handshake against the CA; >0 = the
# chain was validated (a -k would give the same expiry with a WRONG
# cert):
_cert_served() {
    curl -fsS --max-time 15 "http://$VM_IP:8428/api/v1/query" \
        --data-urlencode 'query=probe_ssl_earliest_cert_expiry{instance=~"registry.*"} > 0' 2>/dev/null \
      | jq -e '.data.result | length > 0' >/dev/null
}
gate_diag "obs-cert-servido-medido" \
    '_promql "probe_success{job=\"blackbox-registry\"}"; kubectl -n observability logs deploy/blackbox --tail=10 2>/dev/null' \
    poll 600 15 _cert_served

# (5) obs-deadman-firing: the rule evaluates (vector(1) ALWAYS firing
# — its value is its ABSENCE on the phone):
_deadman_firing() {
    curl -fsS --max-time 15 "http://$VMALERT_IP:8880/api/v1/alerts" 2>/dev/null \
      | jq -e '.data.alerts[]? | select((.name // .alertname) == "DeadmanAegis" and .state == "firing")' \
        >/dev/null
}
gate_diag "obs-deadman-firing" \
    'curl -fsS --max-time 15 "http://$VMALERT_IP:8880/api/v1/alerts" 2>/dev/null | jq . 2>/dev/null | head -n 40' \
    poll 600 15 _deadman_firing

# ── 85.13 the morning question, asked once at birth ───────────────
# image-watch runs on a cron (job-dsl, `H 6 * * *`) and pushes its
# own heartbeat; ImageWatchSilent goes off when that heartbeat is
# absent. On a fresh instance the first cron is up to a day away, so
# without this the alert would be a chronic red for the first 24
# hours — a red that trains the operator to ignore it, which is the
# one thing the rules file forbids. Firing it once here is what makes
# "silent" mean "it stopped", and not "it has not started yet". It is
# a gate because the job never fails over an image (those become
# metrics): if it fails, the watch itself is broken.
gate "obs-image-watch-primera-corrida" jenkins_build_retry image-watch 1200 2

# ── the phone's credential, shown ONCE (§3) ────────────────────────
# Only HERE and not when it is minted: ntfy is already alive and the
# operator can subscribe the app right away. W-01: the value does NOT
# pass through this pane (tmux/script/transcripts record it) — it goes
# to tmpfs and is read from ANOTHER terminal, like the age ceremony.
# No QR: generating one would require a new dependency (qrencode); the
# app subscribes by URL.
if [[ "$NTFY_OPERATOR_NEW" == "true" ]]; then
    NTFY_OP_SHM="/dev/shm/aegis-ntfy-operador-$$"
    ( umask 077; run_cmd install -m 600 "$OPF" "$NTFY_OP_SHM" )
    # The instruction is built and not written flat because under
    # EDGE=local it would be an instruction that DOES NOT WORK, which
    # is worse than none: the phone only reaches the channel if the
    # bridge listens on a LAN address AND the phone was taught to trust
    # aegis' CA — there is no public certificate on this edge. An
    # operator following a step that cannot work concludes the platform
    # is broken, and they are not wrong to.
    NTFY_STEPS=(
        "1. Install the ntfy app (F-Droid / Play / App Store)."
        "2. Subscribe to the topic:  server https://ntfy.$ROOT_DOMAIN — topic aegis-alertas"
    )
    if [[ "${EDGE:-cloudflare}" == local ]]; then
        NTFY_STEPS+=(
           "   EDGE=local: that address is this machine's bridge (${EDGE_BIND_IP:-127.0.0.1})."
           "   On 127.0.0.1 the channel does NOT leave this host: no phone reaches it"
           "   and the heartbeat is read from here. With the bridge on a LAN address"
           "   the phone reaches it, but it first has to trust the internal CA —"
           "   the certificate is aegis' own and no phone knows it."
        )
    fi
    NTFY_STEPS+=(
        "3. User: operador. The password is read from ANOTHER terminal"
        "   (NOT this pane):  cat $NTFY_OP_SHM"
        "4. In a few minutes the app should show the DeadmanAegis heartbeat."
        "   (if you lose the password: sops -d .state-secrets/ntfy_operador_pass.enc)"
        "5. When you continue, the init deletes the copy in /dev/shm."
    )
    human_step "ntfy credential for the phone app (ONCE)" "${NTFY_STEPS[@]}"
    run_cmd rm -f "$NTFY_OP_SHM"
else
    log_info "ntfy_operador_pass was already in the store — it is not shown again (recoverable with the age key)"
fi

# (6) obs-cadena-alerta-canal — THE gate of the phase: the heartbeat
# REACHED the topic (rule → Alertmanager → bridge → ntfy, complete).
# Watching the watchman is MEASURED at birth, not declared (Disease
# E). Poll over the PUBLIC channel (the same one the phone uses) with
# the operator's credential — the password through a netrc in tmpfs,
# never argv (A27).
# The PUBLIC channel is a different path on each edge and the gate
# exercises whichever one this instance has, end to end: under
# cloudflare, DNS + the tunnel + traefik + ntfy; under local, sslip.io
# + the host bridge on EDGE_BIND_IP + traefik on websecure + ntfy. The
# chain it measures — rule, Alertmanager, bridge, topic — is the same
# one, and it is the reason this gate did not move: it has a subject
# under both edges, and it is the one gate this phase exists for:
( umask 077; printf 'machine ntfy.%s login operador password %s\n' \
    "$ROOT_DOMAIN" "$(cat "$OPF")" > "$SECRETS_TMP/ntfy-operador.netrc" )
_alert_reached_ntfy() {
    curl -fsS --max-time 30 --netrc-file "$SECRETS_TMP/ntfy-operador.netrc" \
        "https://ntfy.$ROOT_DOMAIN/aegis-alertas/json?poll=1" 2>/dev/null \
      | grep -qiE 'DeadmanAegis|latido'
}
gate_diag "obs-cadena-alerta-canal" \
    'kubectl -n observability logs deploy/ntfy-bridge --tail=15 2>/dev/null; kubectl -n observability logs deploy/alertmanager --tail=15 2>/dev/null; kubectl -n observability logs deploy/ntfy --tail=10 2>/dev/null' \
    poll 900 20 _alert_reached_ntfy

# (7) obs-grafana-provisionado: the provisioning from git landed — 0
# datasources with a Healthy pod is exactly the failure that "Healthy"
# does not see. In-cluster through the Service; credential via netrc
# (A27):
( umask 077; printf 'machine %s login admin password %s\n' \
    "$GRAFANA_IP" "$(cat "$GRAF_PASS")" > "$SECRETS_TMP/grafana-admin.netrc" )
_grafana_provisioned() {
    curl -fsS --max-time 15 "http://$GRAFANA_IP:80/api/health" 2>/dev/null \
      | jq -e '.database == "ok"' >/dev/null || return 1
    local n
    n="$(curl -fsS --max-time 15 --netrc-file "$SECRETS_TMP/grafana-admin.netrc" \
        "http://$GRAFANA_IP:80/api/datasources" 2>/dev/null | jq -r 'length' 2>/dev/null)"
    [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 3 ))
}
gate_diag "obs-grafana-provisionado" \
    'kubectl -n observability get pods -l app.kubernetes.io/name=grafana 2>/dev/null; kubectl -n observability logs deploy/grafana --tail=20 2>/dev/null' \
    poll 600 15 _grafana_provisioned

# (8) obs-grafana-tras-access: "the origin answered" ≠ "Access
# intercepted" — never a bare curl against a protected hostname
# (check 90). 200/302 from the ORIGIN (grafana redirects to /login
# with no session); a redirect to cloudflareaccess.com is a failure of
# the helper:
# Under EDGE=local there is nothing to cross: with no zone there is no
# Access application, so a gate named «behind Access» could only pass
# as a lie — green with NOTHING in front of grafana. What is measurable
# there, and what the operator needs to know, is that the whole local
# path answers: sslip.io -> the host bridge -> traefik on websecure
# with the internal CA's certificate -> grafana, which with no session
# redirects to its own login. The SAME helper on purpose (check 90 asks
# for it and is right: it is the one that tells the origin apart from
# an interception, and with no service token in the store it says so
# and goes the direct way), and a DIFFERENT name, because a gate's name
# is its contract.
if [[ "${EDGE:-cloudflare}" == cloudflare ]]; then
    gate_diag "obs-grafana-tras-access" \
        'kubectl -n infra-edge logs deploy/cloudflared --tail=15 2>/dev/null' \
        poll 600 10 edge_origin_responds "https://grafana.$ROOT_DOMAIN" '^(200|30[12])$'
else
    gate_no_subject "obs-grafana-tras-access" \
        "EDGE=local: there is no Cloudflare Access in front of grafana — with no zone there is no application to intercept anything and grafana's own login is the only lock. That the hostname ANSWERS is measured right below, and it is a different fact"
    gate_diag "obs-grafana-responde-con-login" \
        'kubectl -n observability logs deploy/grafana --tail=15 2>/dev/null; systemctl is-active aegis-edge-https.socket 2>/dev/null' \
        poll 600 10 edge_origin_responds "https://grafana.$ROOT_DOMAIN" '^(200|30[12])$'
fi

# (9) obs-ntfy-publico-responde: the channel reaches the phone AND
# deny-all is active — publishing without a credential must give a 403
# (an open ntfy would be a spam relay with our domain on it). A bare
# curl ON PURPOSE: ntfy goes without Access (the app does not present
# a service token).
# «Public» means a different path on each edge and the gate is honest
# under both: under cloudflare, the internet; under local, the host
# bridge on EDGE_BIND_IP — which on 127.0.0.1 is this machine and
# nothing else. What it measures does not change with the edge: that
# the channel ANSWERS and that publishing without a credential is
# REFUSED. An ntfy open on a LAN is a relay just the same:
_ntfy_public_ok() {
    local health published
    health="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
        "https://ntfy.$ROOT_DOMAIN/v1/health" 2>/dev/null)" || return 1
    [[ "$health" == "200" ]] || return 1
    published="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
        -d 'probe with no credential (gate obs-ntfy-publico-responde)' \
        "https://ntfy.$ROOT_DOMAIN/aegis-alertas" 2>/dev/null)" || return 1
    [[ "$published" == "403" ]]
}
# The evidence names the suspect of THIS edge: under cloudflare the one
# in between is cloudflared, under local the host bridge. A diagnosis
# that prints nothing is a mute timeout with extra steps (H7):
NTFY_DIAG='kubectl -n observability logs deploy/ntfy --tail=15 2>/dev/null; kubectl -n infra-edge logs deploy/cloudflared --tail=10 2>/dev/null'
if [[ "${EDGE:-cloudflare}" == local ]]; then
    NTFY_DIAG='kubectl -n observability logs deploy/ntfy --tail=15 2>/dev/null; systemctl status aegis-edge-https.socket aegis-edge-https.service --no-pager --lines=10 2>/dev/null'
fi
gate_diag "obs-ntfy-publico-responde" "$NTFY_DIAG" \
    poll 600 15 _ntfy_public_ok

# The closing line says what THIS instance got, and not what the other
# edge would have got: a summary that names a door nobody installed is
# the cheapest lie there is, and it is the one that gets believed.
if [[ "${EDGE:-cloudflare}" == cloudflare ]]; then
    OBS_CLOSING="Grafana provisioned 100% from git behind Access"
else
    OBS_CLOSING="Grafana provisioned 100% from git, reachable only through the host bridge on ${EDGE_BIND_IP:-127.0.0.1} and with no Access in front (its login is the only lock); no tunnel, so the cloudflared family of rules has no subject"
fi
log_ok "OBSERVABILITY COMPLETE: metrics/logs/events flowing, B11 \
measuring what is SERVED, deadman → Alertmanager → bridge → ntfy \
proven end to end, $OBS_CLOSING."
