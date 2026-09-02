#!/usr/bin/env bash
# PHASE 87 — the AI subsystem: the card as a service.
#
# WHY 87, after 85. Everything this phase deploys depends on things the
# earlier phases guarantee and on nothing this one could bring forward:
# the internal registry with TLS (40), the signing key and the admission
# policy in Enforce (80), and the observability that will watch it (85).
# The ai-system namespace is BORN carrying the tenant enforce label, so
# it must never exist during a window in which Kyverno would admit an
# unsigned pod — which is another way of saying this phase cannot run
# before 80.
#
# THE SUBSYSTEM IS OPTIONAL, AND THAT IS THE FIRST THING IT ASKS. An
# instance with no card, or with no interest in AI, is not a degraded
# instance: it is the normal one. `AI` in aegis.conf takes three values
# and each one is a different phase:
#
#   no    (the default)  nothing is deployed, and every gate this phase
#                        would emit is declared WITHOUT A SUBJECT — not
#                        omitted. A gate that stops being written
#                        disappears from gates.jsonl, and three months
#                        later a missing line reads exactly like a green
#                        one.
#   cpu                  the lane that needs no card (speech,
#                        transcription, embeddings, vision). The GPU
#                        gates have no subject; the substrate, the
#                        gateway and the CPU engine are deployed. The GPU
#                        engines land scaled to zero and cost nothing.
#   gpu                  everything, including the device plugin with
#                        time-slicing and the two vLLM lanes.
#
# THE ENGINES ARE BORN OFF, AND THAT IS NOT LAZINESS. A GPU that is on is
# a GPU that draws power and a GPU that can be attacked. Turning it on is
# a human act (`aegis ai start`), which additionally measures the free
# VRAM before it starts — vLLM reserves its KV cache once, at start-up,
# and starting against a dirty card cuts that cache until the next
# restart. THE AUTOMATION ONLY CLOSES.
#
# WHAT THIS PHASE DOES NOT DO. It does not build the AI images and it
# does not invent their digests. Two of the three are built by the
# instance's own pipeline and one is mirrored in from another
# repository; until they exist here there is no digest to write, and the
# kustomization ships the sixty-four-zero marker that says so. This
# phase READS that marker and refuses to deploy on top of it, naming the
# command that fixes it. A phase that deployed anyway would leave three
# ImagePullBackOffs and an operator reading pod events to discover
# something the manifest already said.
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"
# CR-6 in-VM report #14: this phase MUTATES the platform repo — the
# local clone may be behind the remote (a manual fix by the operator on
# GitHub during a resume). Synchronize BEFORE touching anything:
platform_repo_sync
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/aegis.key}"

AI_DIR="$PLATFORM_DIR/k8s/base/ai-system"
GPU_DIR="$PLATFORM_DIR/k8s/base/gpu"
AI_NS=ai-system
# The default is `no` and it is derived HERE, in the phase's own
# subshell. Every phase runs in `( source "$p" )`, so a default applied
# by config_validate died with phase 00: on an instance whose conf was
# written before this key existed, `set -u` would kill the phase with
# «unbound variable» — the exact class check 115 watches on the edge.
AI="${AI:-no}"

# ── 87.0 does this instance have a subject at all? ─────────────────
if [[ "$AI" != "cpu" && "$AI" != "gpu" ]]; then
    [[ "$AI" == "no" ]] || \
        die "AI=\"$AI\" in aegis.conf is not a value this phase knows (no | cpu | gpu) — an unrecognised value is not the same as «no», and guessing which one it meant is how a subsystem gets half deployed"
    log_info "AI=no: this instance does not carry the AI subsystem"
    log_info "  (the manifests DO travel in the seed — nothing is missing; what is missing is a reason to deploy them)"
    for g in ai-images-pinned gpu-driver-minimum inotify-ceiling-for-the-device-plugin \
             gpu-units-advertised ai-secrets-encrypted ai-pvcs-bound \
             ai-gateway-responds ai-controller-observes-the-mode; do
        gate_no_subject "$g" "AI=no in aegis.conf: this instance deploys no AI subsystem, so there is nothing to measure. It is a NOTICE, not an approval"
    done
    log_ok "phase 87 with no subject: AI is off on this instance, and it is said out loud in gates.jsonl"
    return 0
fi

log_info "AI=$AI — deploying the AI subsystem"

# The tmpfs opens HERE, and not down in 87.3 where the secrets of this
# phase are born, because 87.1a fires Jenkins builds and lib/jenkins.sh
# materialises the admin netrc inside $SECRETS_TMP. Run of 2026-09-01:
# it was opened in 87.3, the build of ai-gateway ran first, and the
# credential file resolved to the empty string — Jenkins answered 401
# and the phase reported «the Jenkins API is down or the job does not
# exist» about a job that was there, with its main branch indexed. The
# same shape as the 80 ordering bug: a section arrived without its
# precondition, and the symptom surfaced far from the cause.
# It is opened AFTER the no-subject return: an instance with AI=no has
# no reason to create a tmpfs, and the trap is per phase either way.
secrets_workdir

# ── 87.1 the images, BEFORE anything is created ────────────────────
# First, because a subsystem deployed onto digests of zeros is three
# pods in ImagePullBackOff and an operator reading events to find out
# what the manifest already said. The marker is deliberately, obviously
# false: sixty-four zeros, the same convention the app templates'
# overlays ship with.
_ai_images_pinned() {
    AI_IMAGES_NEEDED="$AI_IMAGES_NEEDED" python3 - "$AI_DIR/kustomization.yaml" <<'EOF'
import os, sys, yaml
k = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
zeros = "sha256:" + "0" * 64
needed = set((os.environ.get("AI_IMAGES_NEEDED") or "").split())
bad = [i.get("name", "?") for i in (k.get("images") or [])
       if i.get("digest", zeros) == zeros
       and i.get("name", "").rsplit("/", 1)[-1] in needed]
if not (k.get("images") or []):
    print("the kustomization declares no `images:` block at all: nothing pins "
          "the AI images and every manifest would deploy a bare name", file=sys.stderr)
    sys.exit(1)
if bad:
    print("still on the sixty-four-zero marker: " + ", ".join(bad), file=sys.stderr)
    sys.exit(1)
EOF
}

# WHICH ROWS THIS LANE ACTUALLY NEEDS, and this is a real distinction
# and not a shortcut. Under AI=cpu the GPU engines are synced with zero
# replicas: nothing ever pulls their image. Demanding a digest for them
# would make a cpu-only instance pay the GPU engine's build — measured
# in hours on a domestic uplink — for an image no pod will open. And
# the marker left in that row is not a lie there: it says «this image
# was never built here», which under AI=cpu is exactly true. A digest
# invented to satisfy a gate would be the lie.
if [[ "$AI" == "gpu" ]]; then
    AI_IMAGES_NEEDED="ai-gateway aegis-ai-vllm aegis-engine-cpu"
else
    AI_IMAGES_NEEDED="ai-gateway aegis-engine-cpu"
fi

# ── 87.1a the images are BUILT, not demanded ───────────────────────
# Until 2026-08-31 this phase opened by DEMANDING the images already
# pinned, and on a fresh instance that could never be true: nobody had
# built anything, so `AI=gpu` was an answer the wizard offered and the
# init could not serve. The phase now produces what it needs and then
# verifies it, which is the same shape phases 50 and 80 already have
# (`jenkins_build_retry ci-images`, `mirror-images`, `base-images`).
#
# IDEMPOTENT BY MEASUREMENT, not by a flag: whatever is already pinned
# is not rebuilt. A re-run of this phase over a working instance fires
# nothing.
#
# The timeouts are not decoration either. The CPU lane resolves and
# unpacks wheels of hundreds of MB; the GPU engine downloads a CUDA
# 12.8 torch and its own Jenkinsfile declares four hours, because on a
# domestic uplink the first build is measured in hours and a timeout
# that cuts it would turn a slow success into a red that says nothing.
_ai_row_digest() {
    python3 - "$AI_DIR/kustomization.yaml" "$1" <<'EOF'
import sys, yaml
k = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
zeros = "sha256:" + "0" * 64
for i in (k.get("images") or []):
    if i.get("name", "").rsplit("/", 1)[-1] == sys.argv[2]:
        d = i.get("digest", zeros)
        if d != zeros:
            print(d)
            sys.exit(0)
sys.exit(1)
EOF
}

# AND WHETHER THIS REGISTRY ACTUALLY HOLDS IT, SIGNED.
#
# The pin is a line in a file. It says which image this installation
# decided to run; it does not say that the image is reachable, and it
# says nothing at all about WHICH registry holds it. Those are three
# different claims and the skip above used to make all three from the
# first one.
#
# The verification is the same one phase 80 already does over the
# canary, deliberately: same key, same CA, same direct-IP route (the
# host does not resolve .svc, and the registry's cert carries the IP in
# its SANs). --insecure-ignore-tlog is not TOFU — the signature is
# fully checked against cosign.pub; only the public transparency log is
# skipped, and it was never used here (--tlog-upload=false, a private
# registry).
_ai_image_signed_here() {   # <image> <digest> ; 0 = it is here and signed
    DOCKER_CONFIG="$SECRETS_TMP/docker" cosign verify \
        --key "$PLATFORM_DIR/k8s/base/platform/cosign/cosign.pub" \
        --registry-cacert "$SECRETS_TMP/aegis-ca.crt" \
        --insecure-ignore-tlog=true \
        "$REGISTRY_CLUSTER_IP:5000/$1@$2" >/dev/null 2>&1
}

# THE BASES, BEFORE ANY BUILD. Each AI Containerfile ships with a
# `__FROM_X__` placeholder instead of a base, and the pipeline's own
# preflight refuses to build while it is still there — correctly: a
# base that did not come through the mirror was neither scanned nor
# signed, and a pod built on it is rejected at admission.
#
# Resolving is a WRITE to the platform repo, and the build reads the
# Containerfile from the REMOTE, not from this working tree, so the
# commit and the push are part of the step and not housekeeping after
# it. Run of 2026-09-01: the resolver already existed and was correct,
# and nothing called it before building — the same shape as every
# other hole this phase had, a section that arrived without its
# precondition.
#
# Idempotent: an already-resolved base reports so and writes nothing,
# and git_commit_if_changes has nothing to commit.
# What is about to be BUILT is the instance's copy, not the seed's.
# If a fix to the product has not been brought over, the build fails
# with the error that was already corrected — say it before firing,
# not after twenty minutes.
seed_drift_report ai/engine-gpu/Containerfile ai/engine-gpu/Jenkinsfile \
                  ai/engine-cpu/Containerfile ai/engine-cpu/Jenkinsfile

run_cmd "$AEGIS_ROOT/libexec/aegis-ai" bases
git_commit_if_changes "$PLATFORM_DIR" \
    "fix(ai): AI Containerfile bases resolved against the internal registry, by digest"
git_push_verified "$PLATFORM_DIR"

# The verification below talks to the registry, so it needs the
# registry's credentials and CA in tmpfs. Idempotent: it re-reads them
# from the cluster and rewrites the same files.
registry_creds "$REGISTRY_HOST_INTERNAL" "$REGISTRY_CLUSTER_IP"

for _img in $AI_IMAGES_NEEDED; do
    if _dig="$(_ai_row_digest "$_img")"; then
        if _ai_image_signed_here "$_img" "$_dig"; then
            log_ok "$_img: pinned at ${_dig:7:12} and this registry holds it, signed — not rebuilt"
            continue
        fi
        # A PIN THAT NAMES AN IMAGE NOBODY HERE HAS.
        #
        # This is the normal state of a NEW installation, not an
        # exotic one: the seed ships pinned rows, and every instance
        # is born with an empty registry. It is also what a restored
        # kustomization, a re-created registry or a garbage collection
        # leaves behind. In all of those the row is honest and the
        # image is absent, and the old skip read the row alone and
        # declared the work done.
        #
        # What made it expensive is that nothing failed here. The
        # phase went green, and the engine's pod stayed pulling — or,
        # worse, was denied at admission for an unsigned digest — and
        # the operator was left reading a symptom several steps away
        # from the phase that caused it.
        #
        # So the question the skip asks is no longer «did somebody
        # decide?» but «is it here?». Rebuilding costs a build;
        # skipping wrongly costs a green phase that installed nothing.
        log_warn "$_img: pinned at ${_dig:7:12}, but no signed image with that digest is in THIS registry — rebuilding. A pin is a note about an image; it is not the image."
    fi
    case "$_img" in
        aegis-engine-cpu) _job=engine-cpu   ; _to=3600  ; _gib=10 ;;
        aegis-ai-vllm)    _job=engine-gpu   ; _to=14400 ; _gib=42 ;;
        # The gateway is a multibranch: its buildable item is the
        # branch, not the folder. Firing the folder does nothing and
        # would look like a success.
        ai-gateway)       _job="ai-gateway-mb/main" ; _to=1800 ; _gib=5 ;;
    esac
    # ROOM BEFORE FIRING, and it is measured because the alternative
    # was measured too: on 2026-09-01 the GPU engine's build was
    # evicted three times for ephemeral-storage, each time after
    # fifteen or twenty minutes of work, and the message the operator
    # saw was «ABORTED» — a word about a pipeline, not about a disk.
    # kaniko unpacks the whole image and writes its layers and its tar
    # on the node: for this engine that is 42 GiB, measured from a node
    # that went from 53 GiB free to eviction at 11, and the
    # kubelet starts evicting with less than ~11 GiB free.
    #
    # Refusing here costs a second. Discovering it there costs twenty
    # minutes and reads like a different problem.
    _room_gib="$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')"
    _need_gib=$(( _gib + 12 ))   # what the build writes + the kubelet's own floor
    if [[ -n "$_room_gib" ]] && (( _room_gib < _need_gib )); then
        die "building $_img needs about ${_gib} GiB of scratch on the node and the kubelet evicts below ~12 GiB free — there are ${_room_gib} GiB. Free space and run this phase again; firing the build now would spend $((_to / 60)) minutes to be evicted. \`aegis image gc\` does not exist yet: the registry keeps every image ever built, and an old one of this engine is usually the biggest thing there."
    fi
    log_info "$_img: not pinned — firing $_job (up to $((_to / 60)) min; needs ~${_gib} GiB free, has ${_room_gib:-?})"
    gate "ai-image-built-$_img" jenkins_build_retry "$_job" "$_to" 2
    # WHICH TAG. Not guessed here, and not written twice: each lane
    # names its tag its own way (engine-cpu the pyproject version plus
    # the short sha, the gateway main-NNNNNN), so a second place
    # deciding it is a second place to drift. The build declares it in
    # the AEGIS_EVENT line — the same line Vector routes to the audit
    # store with a year of retention — and this reads that, for the
    # build number it just waited on.
    _ev="$(jenkins_build_event "$_job" "$JENKINS_LAST_BUILD" "$_img")" || \
        die "build $_job#$JENKINS_LAST_BUILD declared no AEGIS_EVENT for $_img: it cannot say which tag it pushed, so nothing gets pinned — a build that says nothing is not a build that said something else"
    _tag="$(jq -r '.tag // empty' <<< "$_ev")"
    [[ -n "$_tag" ]] || \
        die "the event of $_job#$JENKINS_LAST_BUILD names no tag: $_ev"
    log_info "$_img: the build declares tag $_tag"
    gate "ai-image-pinned-$_img" \
        run_cmd "$AEGIS_ROOT/libexec/aegis-ai" images "$_img:$_tag"
done
unset _img _job _to _dig

gate_diag "ai-images-pinned" \
  'echo "  the AI images this lane needs are pinned in";
   echo "  k8s/base/ai-system/kustomization.yaml, one row each.";
   echo "  aegis-engine-cpu and aegis-ai-vllm are built by this instance from";
   echo "  ai/engine-cpu/ and ai/engine-gpu/; ai-gateway comes from its own";
   echo "  repository (AI_GATEWAY_REPO), through the multibranch the platform seeds.";
   echo "  Under AI=cpu the GPU row stays on the marker ON PURPOSE: those";
   echo "  engines land at zero replicas and nothing pulls them.";
   echo "  See docs/protocols/ai-subsystem.md §3, and read ai/engine-gpu/Containerfile";
   echo "  before building that one: it ships DECLARED AS NOT VERIFIED."' \
  _ai_images_pinned

# ── 87.2 the GPU plane ─────────────────────────────────────────────
if [[ "$AI" == "gpu" ]]; then
    # THE DRIVER, and the honest floor. The subsystem's design documents
    # used to say the minimum driver version was «not recorded anywhere
    # in this repository» and to treat it as an open question. It is
    # narrower now, and only as narrow as the evidence allows: the
    # subsystem has been observed working on the open-kernel 595.84
    # driver, and the engines are built for a Blackwell consumer card
    # (sm_120), whose compute capability was introduced by the 570
    # series. So the floor demanded here is 570 — the oldest branch that
    # can enumerate the card at all — and NOT 595, which would be
    # writing one machine's measurement as everybody's requirement.
    # Anything between 570 and 595 is untested rather than known-bad,
    # and the gate says so instead of pretending.
    AI_DRIVER_MIN=570
    _driver_ok() {
        command -v nvidia-smi >/dev/null || return 1
        local v major
        v="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ')"
        [[ -n "$v" ]] || return 1
        major="${v%%.*}"
        [[ "$major" =~ ^[0-9]+$ ]] || return 1
        log_info "driver $v (branch $major); the demanded floor is $AI_DRIVER_MIN"
        (( major >= AI_DRIVER_MIN ))
    }
    gate_diag "gpu-driver-minimum" \
      'command -v nvidia-smi >/dev/null && nvidia-smi || echo "  nvidia-smi is not on the PATH: the driver is not installed, or this is not the machine with the card";
       echo "  AI=gpu asks for a card. If this instance has none, AI=cpu is the honest value."' \
      _driver_ok

    # THE INOTIFY CEILING, measured and expensive. The device plugin
    # watches files, and a distro default of 128 instances is a desktop
    # number: it starved the watcher and produced 424 restarts over six
    # days, with the node advertising nvidia.com/gpu: 0 and the
    # Application showing Progressing with every resource Synced. That
    # is the worst possible failure shape — everything the panel
    # inspects says yes. The seed's host bootstrap persists 1024; this
    # gate is what turns that written step into a measured one.
    _inotify_ok() {
        local n
        n="$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)"
        [[ "$n" =~ ^[0-9]+$ ]] || return 1
        log_info "fs.inotify.max_user_instances = $n (1024 is what the host bootstrap persists)"
        (( n >= 1024 ))
    }
    gate_diag "inotify-ceiling-for-the-device-plugin" \
      'sysctl fs.inotify.max_user_instances 2>&1;
       echo "  remedy: re-run ansible/playbooks/bootstrap-host.yml, which persists this to";
       echo "  /etc/sysctl.d/99-aegis-k3s.conf. Without it the plugin restarts in a loop and";
       echo "  the node advertises 0 GPUs while every Application reports Synced."' \
      _inotify_ok

    argo_sync gpu 300
    # TWO AND NOT «MORE THAN ZERO». Two is the time-sliced count. One
    # means the plugin registered and the slicing ConfigMap did not
    # land — the card is there, the pods schedule, and the second lane
    # will never get a turn. A gate that accepted «at least one» would
    # be green over precisely the bug it exists to catch.
    _gpu_units_two() {
        local n
        n="$(kubectl get nodes -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}' 2>/dev/null \
             | tr ' ' '\n' | sort -n | tail -1)"
        [[ "$n" == "2" ]]
    }
    gate_diag "gpu-units-advertised" \
      'kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}{\"\t\"}{.status.allocatable}{\"\n\"}{end}" 2>/dev/null;
       kubectl -n kube-system get pods -l name=nvidia-device-plugin-ds 2>/dev/null;
       kubectl -n kube-system logs -l name=nvidia-device-plugin-ds --tail=25 2>/dev/null;
       echo "  0 units: the plugin cannot see the card (driver, toolkit, or k3s not restarted after installing it).";
       echo "  1 unit:  the plugin registered and the time-slicing ConfigMap did NOT land."' \
      poll 300 10 _gpu_units_two
else
    gate_no_subject "gpu-driver-minimum" \
      "AI=cpu: this lane needs no card, so there is no driver to measure"
    gate_no_subject "inotify-ceiling-for-the-device-plugin" \
      "AI=cpu: the device plugin is not deployed, so its file watcher has no ceiling to starve"
    gate_no_subject "gpu-units-advertised" \
      "AI=cpu: no device plugin, so the node advertises no units — the GPU engines land scaled to zero and cost nothing"
fi

# ── 87.3 the two secrets the ksops generator names ─────────────────
# ai-system's secret-generator lists both files and NEITHER travels in
# the seed: they are born here, encrypted to this instance's age key.
# A generator naming a file nobody writes leaves the whole Application
# unable to render ("ksops: no such file") while ArgoCD reports Healthy
# about nothing — the failure that cost garage-system a clean instance.
# Check 145 derives that obligation from the generator itself.
# (the tmpfs is already open: it is created at the top of the phase,
# because 87.1a talks to Jenkins long before this point.)
REG_HOST="$REGISTRY_HOST_INTERNAL"   # single source (P3 audit)
# gen_or_restore reads back the SAME registry password phase 40 stored:
# regenerating it here would produce a regcred that does not match the
# htpasswd the registry is serving. One origin, derived in this same
# process, exactly as phase 40 does it.
REG_PASS="$(gen_or_restore registry_pass gen_password_b64)"
derive_htpasswd_and_regcreds aegis-dev "$REG_PASS" "$REG_HOST"
make_enc_secret regcred-internal "$AI_NS" \
    "$PLATFORM_DIR/k8s/base/ai-system/secret-regcred-internal.enc.yaml" \
    --type kubernetes.io/dockerconfigjson \
    ".dockerconfigjson=$SECRETS_TMP/dockerconfig.json"

# THE KEY FILE IS BORN EMPTY, AND IT IS BORN. There are no organizations
# with AI on a freshly started instance, so there is no hash to write —
# but the file has to exist or the Application does not render, and the
# gateway has to be able to read an empty roster rather than crash on a
# missing mount. `aegis ai key issue` adds entries one at a time; it
# never rewrites this file, because it is SHARED across organizations
# and a mistyped onboarding would overwrite somebody else's row.
#
# Idempotent on purpose: an existing file is left alone. Rewriting it on
# a re-run of this phase would silently revoke every key ever issued.
if [[ -f "$AI_DIR/secret-ai-keys.enc.yaml" ]]; then
    log_info "secret-ai-keys.enc.yaml already exists — NOT touched (rewriting it would revoke every key issued)"
else
    printf '{"claves":[]}\n' > "$SECRETS_TMP/keys.json"
    # --from-file and not --from-literal: byte-preserving. A stringData
    # assembled by hand picks up a byte from the YAML folding, and the
    # gateway compares hashes.
    make_enc_secret ai-keys "$AI_NS" \
        "$AI_DIR/secret-ai-keys.enc.yaml" \
        "keys.json=$SECRETS_TMP/keys.json"
fi
gate "ai-secrets-encrypted" bash -c \
  "test -s '$PLATFORM_DIR/k8s/base/ai-system/secret-regcred-internal.enc.yaml' && test -s '$AI_DIR/secret-ai-keys.enc.yaml'"

# class F audit: no || true to swallow a real failed commit.
git_commit_if_changes "$PLATFORM_DIR" "feat(ai): ai-system secrets (regcred + an empty key roster)"
git_push_verified "$PLATFORM_DIR"

# ── 87.4 the substrate ─────────────────────────────────────────────
argo_sync ai-system 600
# F-B run #15: a sync can die from transient DNS and leave the gate
# passing over the OLD Synced revision. This demands the revision that
# was JUST pushed.
argo_secrets_gate ai-system 300 "$(git -C "$PLATFORM_DIR" rev-parse HEAD)" \
    "$PLATFORM_DIR"

# The volumes, which is where the weights will land. Four of them:
# models-hf (shared by both GPU lanes, read-only), one compilation cache
# per GPU lane (two vLLM processes writing JIT kernels into the same
# volume trip over Triton's locks), and the CPU lane's models.
# BOUND, OR WAITING FOR A CONSUMER THE DESIGN KEEPS AT ZERO.
#
# `local-path` binds on first consumer. The GPU engines declare no
# `replicas`, so Kubernetes gives them 1 and the mode controller takes
# them to 0 within a few loops — which is the design, and which means
# a lane's cache volume binds only if its pod happened to be scheduled
# during that window. Measured 2026-09-01 on the first real run:
# engine-llm-cache bound, engine-mt-cache did not, and the phase sat
# 600 s waiting for a state the design prevents.
#
# So the question changes to the one that is actually true: no volume
# is FAILED, and every one that is not bound is waiting for a consumer
# that is deliberately off. It binds by itself the first time that
# engine runs, which is the honest moment for it to happen. Saying it
# out loud beats a green that had to be arranged.
_pvcs_bound() {
    local want=4 total bound pending line name phase
    total=0; bound=0; pending=""
    while read -r name phase; do
        [[ -n "$name" ]] || continue
        total=$(( total + 1 ))
        case "$phase" in
            Bound)   bound=$(( bound + 1 )) ;;
            Pending) pending="$pending $name" ;;
            *)       log_warn "  PVC $name is in $phase, which is neither bound nor waiting"; return 1 ;;
        esac
    done < <(kubectl -n "$AI_NS" get pvc \
                -o jsonpath='{range .items[*]}{.metadata.name} {.status.phase}{"\n"}{end}' 2>/dev/null)
    [[ "$total" == "$want" ]] || return 1
    for name in $pending; do
        kubectl -n "$AI_NS" get events --field-selector "involvedObject.name=$name" \
            -o jsonpath='{range .items[*]}{.reason}{"\n"}{end}' 2>/dev/null \
          | grep -q '^WaitForFirstConsumer$' || return 1
        log_info "  PVC $name: waiting for its first consumer, and its engine is off by design — it binds when that engine first runs"
    done
    return 0
}
gate_diag "ai-pvcs-bound" \
  'kubectl -n ai-system get pvc 2>/dev/null;
   kubectl -n ai-system get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 10;
   echo "  local-path binds on first consumer for some storage classes: if they sit Pending";
   echo "  with no events, check that the storage class exists and is the default."' \
  poll 300 5 _pvcs_bound

# ── 87.5 the door responds ─────────────────────────────────────────
# WHAT THIS MEASURES AND WHAT IT DOES NOT. `readyReplicas` on the
# gateway means the KUBELET got a 200 from /healthz on port 8081: the
# process is up and answering on the internal door. It does NOT prove
# that a tenant can reach it with a key — that path needs an
# organization, a key and an egress rule, none of which exist on a
# freshly started instance, and inventing them here to have something
# greener to print would be measuring a fixture instead of the system.
# The consumer test is step 5 of the protocol, and it is written there
# as the thing that is still owed.
gate_diag "ai-gateway-responds" \
  'kubectl -n ai-system get deploy ai-gateway -o wide 2>/dev/null;
   kubectl -n ai-system get pods -l app=ai-gateway 2>/dev/null;
   kubectl -n ai-system describe pods -l app=ai-gateway 2>/dev/null | tail -n 30;
   echo "  the gateway mounts four ConfigMaps and one Secret; all must exist or the pod";
   echo "  does not start. ai-ruteo and ai-registro come out of the contract generator."' \
  wait_rollout "$AI_NS" deploy/ai-gateway 600

# ── 87.6 the controller observes, and the proof is the engines ─────
# THE STRONGEST GATE IN THIS PHASE, and the reason it is written this
# way instead of asking the controller whether it feels well.
#
# The GPU engines declare NO `replicas` field (see engine-llm.yaml for
# why), so Kubernetes gives them the default of 1. The mode is unset,
# and the controller treats anything it does not recognise — the absent
# value included — as `cerrado`: "when in doubt, the GPU goes off". So
# within a few of its loops both engines must be at zero.
#
# Reaching zero proves the whole chain end to end, and nothing else in
# this phase proves any of it: the controller's pod is up, its token is
# mounted, it reached the APISERVER (which exercises the egress
# NetworkPolicy — the one place a node with a public InternalIP fails,
# and the reason netpol.yaml can afford not to hardcode one address),
# its Role really permits deployments/scale on these two names, and it
# read the ConfigMap. If any link is broken the engines stay at one, and
# on a `gpu` instance that means a card quietly powered up.
_engines_off() {
    local e reps
    for e in engine-llm engine-mt; do
        reps="$(kubectl -n "$AI_NS" get deploy "$e" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")"
        [[ "$reps" == "0" ]] || return 1
    done
}
gate_diag "ai-controller-observes-the-mode" \
  'kubectl -n ai-system get deploy 2>/dev/null;
   kubectl -n ai-system logs deploy/ai-modo-controller --tail=30 2>/dev/null;
   echo "  the engines stayed up, so the controller did NOT act. In order:";
   echo "   · its pod is not ready            -> the digest, the quota, or its Secret";
   echo "   · «could not read the mode»       -> its egress NetworkPolicy does not reach";
   echo "     the apiserver. That happens when the node InternalIP is PUBLIC: the rule";
   echo "     in netpol.yaml covers the three private ranges, and a node outside them";
   echo "     needs one more ipBlock with that address.";
   echo "   · «forbidden»                     -> its Role names other Deployments"' \
  poll 180 5 _engines_off

log_ok "AI subsystem deployed (AI=$AI): substrate, netpols and volumes in place, the door \
answering on the internal port, and the controller proven by the engines it took to zero. \
The engines are OFF, which is the resting state — opening the card is \`${AEGIS_CMD:-aegis} ai start\`, \
a human act, and the automation only ever closes"
