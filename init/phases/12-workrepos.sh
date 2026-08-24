#!/usr/bin/env bash
# PHASE 12 — work repos: the init CREATES and SEEDS them (D10).
# ISOLATION: the v2 repos are DISPOSABLE and our own (ops-stack-v2 /
# hello-aegis-v2 by default) — the init writes commits, tags, settings
# and webhooks to them; they must NEVER be the real v1 repos. The
# operator does not create repos by hand (the mission: the init asks
# and does).
#
# It also fixes the v2 sequencing bug at the root: phase 15 registers
# deploy keys and gates an ls-remote against repos that phase 25 used
# to create only afterwards — now they exist from here on.
#
# Idempotence: the init's repos carry the topic
# `aegis-v2-disposable` (a marker). Re-run: exists+marked → reuse;
# exists UNMARKED → RED (it could be a real repo).
#
# Credential: the already-authenticated gh session (phase 00 gate) —
# the init has no PAT of its own (D10 removed the PAT from the flow: a
# token minted for a consumer that no longer exists was free attack
# surface). Git pushes from the host go over https with gh's
# credential helper; the SSH deploy keys are left for the in-cluster
# consumers (phase 15).
set -euo pipefail
CONF="$AEGIS_HOME/aegis.conf"; source "$CONF"

MARK_TOPIC="aegis-v2-disposable"

# ── 12.0 git on the host: identity + credential + known_hosts ──────
git config --global user.name  >/dev/null 2>&1 || \
    run_cmd git config --global user.name "aegis-init"
git config --global user.email >/dev/null 2>&1 || \
    run_cmd git config --global user.email "aegis-init@${ROOT_DOMAIN}"
run_cmd gh auth setup-git    # https helper (idempotent)

# github.com known_hosts from the T1 pins in the jenkins values (the
# SINGLE SOURCE of host keys, verified against /meta in phase 00) —
# never TOFU (no accept-first-connection):
KH="$HOME/.ssh/known_hosts"
run_cmd mkdir -p "$HOME/.ssh"; run_cmd chmod 700 "$HOME/.ssh"
grep -q 'github.com ssh-ed25519' "$KH" 2>/dev/null || run_cmd bash -c \
  "grep -Eo 'github\.com (ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa) [A-Za-z0-9+/=]+' \
     '$PLATFORM_DIR/k8s/base/platform/jenkins/values.yaml' >> '$KH'"
gate "known-hosts-github" grep -q 'github.com ssh-ed25519' "$KH"

# ── 12.1 create/reuse each repo (idempotent via the marker) ────────
ensure_repo() {
    local repo="$1" desc="$2"
    if gh repo view "$GH_OWNER/$repo" >/dev/null 2>&1; then
        # it exists: is it OURS (marked) or a real repo? That
        # distinction is the heart of the isolation:
        if gh api "repos/$GH_OWNER/$repo/topics" --jq '.names[]' \
             2>/dev/null | grep -qx "$MARK_TOPIC"; then
            log_info "repo $repo already exists with marker $MARK_TOPIC — reusing it"
        else
            log_warn "repo $GH_OWNER/$repo EXISTS and does NOT have the marker"
            # P0.1 audit: under --non-interactive this is NOT
            # auto-confirmed — the seed does a push --force and marking
            # someone else's repo as disposable would TRAMPLE it.
            # Unattended does not decide about what is not marked as
            # ours:
            ni_mode && die "repo $GH_OWNER/$repo exists WITHOUT the marker $MARK_TOPIC and there is no operator to decide — pick another name in the conf, or mark the repo by hand if it really is disposable"
            gate_red "use $GH_OWNER/$repo as a DISPOSABLE v2 repo — if it is a real repo (v1), ABORT and pick another name with --configure"
            run_cmd gh api -X PUT "repos/$GH_OWNER/$repo/topics" \
                -f "names[]=$MARK_TOPIC"
        fi
    else
        run_cmd gh repo create "$GH_OWNER/$repo" --private \
            --description "$desc"
        run_cmd gh api -X PUT "repos/$GH_OWNER/$repo/topics" \
            -f "names[]=$MARK_TOPIC"
        log_ok "repo $repo created (private, marked $MARK_TOPIC)"
    fi
    # B4 settings + squash (previously tofu github-repos — D10: gh api
    # is idempotent, no state, no PAT):
    run_cmd gh api -X PATCH "repos/$GH_OWNER/$repo" \
        -F delete_branch_on_merge=false \
        -F allow_squash_merge=true \
        -f squash_merge_commit_title=COMMIT_OR_PR_TITLE \
        -f squash_merge_commit_message=COMMIT_MESSAGES >/dev/null
    gate "b4-false-$repo" bash -c \
      "gh api repos/$GH_OWNER/$repo --jq .delete_branch_on_merge | grep -qx false"
}
ensure_repo "$PLATFORM_REPO" "aegis v2 — platform (DISPOSABLE test repo)"
ensure_repo "$APP_REPO"      "aegis v2 — canary (DISPOSABLE test repo)"

# ── 12.2 seed PLATFORM_REPO with the artifact's platform/ ──────────
# platform/ IS the working tree (already rendered by phase 10):
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
# class F audit: commit conditioned on real staged content, with no ||
# that would swallow a legitimate commit failure (hook, identity,
# index.lock):
git_commit_if_changes "$PLATFORM_DIR" \
    "feat(bootstrap): initial v2 platform (aegis-init seed)"
# DELIBERATE push --force (run #4): on a run from a snapshot the local
# .git is new and the remote carries the previous run's history →
# "fetch first" with a misleading network message. The remote is OURS
# and disposable BY CONSTRUCTION (ensure_repo verified the marker or
# stopped at a RED above); the local working tree is the seed's source
# of truth. Never apply this pattern to a real repo:
run_cmd retry_net 3 git -C "$PLATFORM_DIR" push -u --force origin main || \
    die "platform push failed — check the network/gh permissions and --from 12"
gate "platform-repo-sembrado" retry_net 3 bash -c \
    "git ls-remote https://github.com/$GH_OWNER/$PLATFORM_REPO.git HEAD | grep -q ."

# ── 12.3 seed APP_REPO with the canary ─────────────────────────────
# H6 run #15: the "don't re-seed if it has content" rule left the
# PREVIOUS run's .argocd-source-hello-aegis.yaml from the write-back
# ALIVE — ArgoCD treats it as a parameter override and it trampled the
# newTag → the canary asked for a nonexistent tag (ImagePullBackOff)
# and phase 70's alignment had no effect (it looked at the
# kustomization, not at the effective source). THE catalogued family
# (leftovers from previous runs) bit through the file the seed does
# NOT contain: writing on top does not guarantee state-equals-seed.
# Fix of the CLASS: if phase 12 runs, the canary is ALWAYS seeded with
# an ORPHAN history + push --force (the same contract as the platform
# seed: repos marked disposable BY CONSTRUCTION — ensure_repo verified
# the marker or stopped above). Running phase 12 IS asking for a
# greenfield canary; the builds/write-backs of the run in progress
# live in later phases, which phase 12's marker protects (an explicit
# --from 12 = a deliberate re-seed, documented here):
{
    SEED_TMP="$(mktemp -d)"
    run_cmd cp -r "$AEGIS_ROOT/seed/canary/." "$SEED_TMP/"
    # the canary's Jenkinsfile is INSTANTIATED from the platform
    # template (single source — there is no second copy to drift).
    # IMAGE stays fixed at 'hello-aegis': it is the canary's identity
    # (the App, the IU's CR and the Deployment all use it); the REPO
    # name is free:
    run_cmd bash -c "sed \"s/CHANGEME-app/hello-aegis/\" \
      '$PLATFORM_DIR/docs/protocols/templates/Jenkinsfile.app' \
      > '$SEED_TMP/Jenkinsfile'"
    # CR-5 run #14: the seed does NOT go through
    # render_platform_placeholders (that is platform/'s business) — the
    # domain of the canary's IngressRoute is rendered HERE, at seeding
    # time. A gate on the result: a live placeholder in the app repo
    # would be a literal Host 'aegis.__ROOT_DOMAIN__':
    run_cmd bash -c "grep -rl '__ROOT_DOMAIN__' '$SEED_TMP' \
      | xargs -r sed -i 's/__ROOT_DOMAIN__/$ROOT_DOMAIN/g'"
    gate "seed-sin-placeholders" bash -c \
      "! grep -rq '__ROOT_DOMAIN__' '$SEED_TMP'"
    run_cmd git -C "$SEED_TMP" init -b main
    run_cmd git -C "$SEED_TMP" add -A
    run_cmd git -C "$SEED_TMP" commit -m \
        "feat: canary hello-aegis v2 (aegis-init seed)" --no-verify
    run_cmd git -C "$SEED_TMP" remote add origin \
        "https://github.com/$GH_OWNER/$APP_REPO.git"
    # --force: the orphan history overwrites the previous run's (H6).
    # The local sha is kept for the state-equals-seed gate:
    SEED_SHA="$(git -C "$SEED_TMP" rev-parse HEAD)"
    run_cmd retry_net 3 git -C "$SEED_TMP" push -u --force origin main || \
        die "canary push failed — check the network/gh permissions and --from 12"
    rm -rf "$SEED_TMP"
}
# the gate validates the RESULT, not the intention (family H6): the
# remote HEAD must be EXACTLY the seed's commit — any leftover
# (.argocd-source-*, old tags in the tree) would imply a different sha:
gate "app-repo-estado-igual-al-seed" retry_net 3 bash -c \
    "git ls-remote https://github.com/$GH_OWNER/$APP_REPO.git refs/heads/main \
     | grep -q '^$SEED_SHA'"

log_ok "Work repos ready and marked disposable: \
$GH_OWNER/$PLATFORM_REPO (platform) + $GH_OWNER/$APP_REPO (canary)"
