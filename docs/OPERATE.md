# OPERATE.md — guide for operating a live instance

This file is for the agent (AI or human) opening a session ON the
machine where the aegis platform is RUNNING (the validation VM or,
in the future, the production host). Its goal: that you can
diagnose and operate without breaking anything and without
re-discovering what was already learned the hard way.

If you are going to MODIFY the artifact → `AGENTS.md` (and do it in
the product repo, not here). For the historical record of how v3
was built → `plan/` and `EJECUTADO.md`, which stay in Spanish
because they are the working record between the operator and
Claude, not the product.

---

## 1. Where you are standing

- The **product** (`AEGIS_ROOT`) is this repo: `bin/ libexec/ lib/
  init/ verify/ seed/`. Read-only for the duration of a run.
  The **instance** (`AEGIS_HOME`) is this machine's living state:
  `platform/ .init-state/ .state-secrets/ aegis.conf`. On the house
  machine the two are still the same folder — `lib/paths.sh` keeps
  that v2 shape working on purpose — but they are two ideas and the
  commands treat them as two.
- The init leaves its state in `$AEGIS_HOME/.init-state/` (`*.done`
  markers per phase + `gates.jsonl`) and its encrypted secrets in
  `$AEGIS_HOME/.state-secrets/` (`*.enc`, encrypted with the age
  key).
- The age key lives in `~/.config/sops/age/aegis.key` (chmod 600).
  For sops/tofu in non-interactive shells ALWAYS export it
  explicitly: `export SOPS_AGE_KEY_FILE=~/.config/sops/age/aegis.key`
  (direnv does not reach non-interactive shells).
- ALWAYS work inside tmux — SSH drops have killed long processes.
  BUT: never turn on tmux pipe-pane/logging during key ceremonies
  (a key got recorded that way once).

## 2. Expected state of a healthy instance

```bash
kubectl get pods -A            # all Running/Completed
kubectl get applications -n argocd
```

Expected: ~19 Apps. MOST of them Synced/Healthy, with up to 3
**OutOfSync/Healthy that are BENIGN and known**: kyverno (CRDs/
defaulting), hello-aegis (the Image Updater's digest pin), root
(cascade). They are NOT incidents; do not "fix" them.

Control-plane namespaces: `argocd`, `infra-edge` (traefik +
cloudflared), `cert-manager`, `registry-system`, `jenkins-system`,
`trivy-system`, `kyverno`. Reference tenant: `org-canary`
(the hello-aegis canary).

Healthy edge: `https://aegis.<domain>` → 200, `argocd.<domain>` →
200, `jenkins.<domain>` → 403 anonymous (that IS success, not a
failure).

## 3. Diagnosis: where to start (in order)

```bash
# 1) The black box of the last run — ALWAYS first:
jq -r 'select(.result!="pass") | "\(.phase) \(.gate) \(.result)"' \
    "$AEGIS_HOME/.init-state/gates.jsonl"

# 2) Apps and their health:
kubectl get applications -n argocd \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

# 3) One specific app that worries you:
kubectl -n argocd get application <app> -o jsonpath='{.status.operationState}' | jq .
kubectl -n <ns> get events --sort-by=.lastTimestamp | tail -20

# 4) Jenkins (the API answers with auth; the anonymous 403 is normal):
kubectl -n jenkins-system get pods
kubectl -n jenkins-system logs jenkins-0 -c jenkins --tail=50
```

Rules of diagnosis:

- **Convergence before measurement**: if something "fails" seconds
  after a change, it is probably still converging. Wait for
  stability BEFORE measuring; never measure `items[0]` of a
  collection with cascading ReplicaSets — measure the CURRENT RS.
- **Transient ≠ failure**: network signatures (dial tcp / i/o
  timeout / lookup / EOF / connection re*) = wait and retry. A
  deterministic error with the same signature 3 times = a real
  cause, stop.
- **One symptom, several causes: discriminate BEFORE touching.**
  The canonical example: "the webhook returns 400" can be (a) a
  desynchronised HMAC or (b) a consequence of something else (e.g.
  a deleted hook, an exhausted RQ downstream). Look at the logs and
  at GitHub's deliveries BEFORE deleting/recreating anything.
  Deleting on a wrong hypothesis has already cost one run.

## 4. Do-not-touch rules (breaking them breaks things silently)

1. **NEVER print Secrets**: not `-o yaml`, not `-o json`, not
   `.data`. `kubectl get secret <n>` with no `-o` for existence;
   lengths with `wc -c` over a file. No exceptions, not even "just
   for debugging".
2. **No `kubectl apply` by hand over managed resources**: this is
   GitOps — ArgoCD with selfHeal REVERTS your patch and leaves
   phantom drift on top. The path is: change in the repo → push →
   sync. If you NEED to patch live (an emergency): pause that App's
   auto-sync FIRST, patch, and know that on resuming, selfHeal goes
   back to git.
3. **A manual sync does NOT inherit the spec's syncOptions**
   (verified live, v3.4.x): a sync triggered by hand with an empty
   `operation.sync` loses CreateNamespace/ServerSideApply. And a
   FAILED manual sync poisons the auto-retry ("will not retry").
   Prefer waiting for the auto-sync; if you sync by hand, propagate
   the options.
4. **`rollout restart` in namespaces with a signature policy**:
   Kyverno does NOT re-mutate UPDATEs without an image change — a
   Deployment admitted PRE-policy that references a tag becomes
   un-restartable (a deterministic deny on the ReplicaSet) until
   the next image bump. Think before restarting pods in
   `org-canary`.
5. **A Secret's `type` is IMMUTABLE**: to change it, a targeted
   `kubectl delete` + selfHeal recreates it from git. Never a
   permanent Replace=true on the App.
6. **An App that is Synced+Healthy does NOT guarantee its Secrets**
   (the KSOPS generators use an explicit list): validate with
   `kubectl get secret` after any change to secrets.
7. **tofu ALWAYS through the wrapper** (`platform/tofu/tofu-apply.sh`):
   bare, the TF_VARs are missing and there are phantom destroys.
8. **No `--insecure`/`accept-first`/`StrictHostKeyChecking=no`**
   in any flow. What is known goes declarative; what is secret goes
   through the operator; TOFU never.
9. **Reverts step by step**, never chained with `&&` — each step
   with its exit code in plain sight.

## 5. Known failure signatures (a shortcut into the catalogue)

The catalogue by class lives in `platform/docs/failure-modes.md`.
A cheat sheet of the ones that come up most while operating:

| Symptom | Probable cause | What to look at |
|---|---|---|
| App in permanent ComparisonError | broken kustomize (YAML/entry) — fatal, do not wait | `kubectl kustomize` of the dir |
| App in intermittent ComparisonError | network (dial tcp/timeout signature) — wait | it retries on its own |
| Build queued forever, init silent | ResourceQuota exhausted | the ns events + the RQ's usage |
| New pod: connection refused to a healthy service | kube-router has not programmed the fresh pod's ipset yet | retry INSIDE the pod (~30s) |
| "no basic auth credentials" on pull | regcred of type Opaque (kubelet ignores it) | `type` must be dockerconfigjson |
| Deterministic webhook 400 | desynchronised HMAC (or one with a trailing `\n`) | GitHub deliveries + logs |
| Cluster DNS broken after a k3s restart | systemd-resolved stub / phantom nameserver | the runbook in v2's `VALIDACION.md` §1.9 |
| Jenkins init "cp" crashes | contaminated emptyDir | `kubectl delete pod --force` (a fresh emptyDir) |
| cloudflared restarts often | reconnection over an intermittent network — NORMAL in dev | nothing, it is expected |
| Pod rejected citing `require-aegis-signature` | unsigned image — the platform WORKING | pipeline: build+scan+sign |
| Pod rejected WITHOUT citing the policy | PSS or quota, NOT Kyverno | the deny message says which |

## 6. The recovery tools

They run out-of-band (never inside the init). All with dry-run by
default where it applies:

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/aegis.key

aegis state backup      # age-encrypted bundle of the 3 states
                        # (.state-secrets, .init-state, tfstate) with
                        # a verified ROUNDTRIP. The age key NEVER goes
                        # into the bundle (guard active).
                        # Writes into $AEGIS_BACKUPS/platform/.
aegis state restore <bundle>   # the inverse; it refuses to overwrite
                               # existing state without --force
aegis rotate                   # with NO arguments: the rotation menu
                               # (see below).
aegis destroy [--yes]          # tofu destroy of the CF edge + tfstate
                               # purge; dry-run shows the plan
```

### Rotating a credential

```bash
aegis rotate list         # inventory, age and radius of each one
```

The menu lists what is rotatable with its AGE and, above all, with
its **radius**: what breaks if that rotation goes wrong. The radius
is printed *before* the confirmation, which is when it is useful.

What it does for each credential: it archives the previous `.enc`
into `.state-secrets/.previo/`, invalidates it in the store, runs
the phase that regenerates it and synchronises the third party, and
**verifies by exercising the real consumer**. That last part is the
one nobody used to do.

Three things worth keeping in mind:

- **It does not start if the network is bad.** A preflight of
  GitHub, Cloudflare, the cluster and the age key before touching
  the first `.enc`. On this machine that is not paranoia: it is what
  keeps you from ending up half-synchronised.
- **It retries the transport, not the verdict.** A timeout is
  retried up to three times; a «Permission denied» or a webhook
  answering 400 is **not**. At that point the remote end already
  answered, and it answered no.
- **If it fails, it does not roll back on its own.** It tells you in
  which of the four places —git, cluster, third party, store— each
  half was left, and with which command to close the gap.
  Afterwards, `aegis rotate continue` resumes the batch.

It refuses to rotate `cosign_*` and the age key (irreducibles, each
with its own protocol in `platform/docs/protocols/`) and delegates
`registry_pass` to `aegis registry rotate`.

It does not commit or push: that is given by a person.

### Asking whether a credential works, without rotating it

```bash
aegis rotate check               # all of the ones in the inventory
aegis rotate check hmac_jenkins  # just one
```

It exercises the REAL consumer of each one: a webhook ping that has
to give 200 *and* a made-up signature that has to give 400; `ssh -T`
with the key from the live Secret; a real login into ArgoCD and into
Jenkins; `tofu plan`; certificates Ready. Four possible results, and
the third matters as much as the others:

| | means |
|---|---|
| `✓ works` | the real consumer accepted it |
| `✗ REJECTS it` | the remote end answered, and it answered no |
| `? could not reach` | the MEASUREMENT failed, not necessarily the credential |
| `! no tooth written` | nobody measures it. **This is not green.** |

### Cloudflare Access, and why `aegis rotate check` has two teeth there

`argocd.<domain>` and `jenkins.<domain>` sit behind Cloudflare
Access. That changes what a `curl` against them means: with no
credential, Cloudflare answers **302 to the login from its own
edge** — the request never enters the tunnel, never touches traefik
and never sees the app.

A check that accepts that 302 as «it responds» stays green with the
whole cluster switched off. That is why everything probing those
hostnames goes through `edge_origin_responds` (`lib/access.sh`),
which crosses Access with the service token and **separates three
outcomes that used to be one**: the origin answered / Access
intercepted / there was no answer.

And that is why `aegis rotate check access_st_id` measures two
things, not one:

| tooth | what it proves |
|---|---|
| **with** the service token → it reaches the ORIGIN | the token works |
| **without** the token → Access intercepts | Access really is protecting |

Without the second, the first would prove nothing: if Access were
down, everybody would reach the origin and the verifier would be
just as green.

The Access credentials are three and the init produces them: the API
token (`cf_access_token`, phase 15) and the two halves of the
service token (`access_st_id` / `access_st_secret`, phase 25, from
the tofu outputs). The two halves are **always rotated together** —
Cloudflare issues them as a pair.

The Access API token is **separate** from the tunnel token on
purpose: Jenkins' `edge-apply` job receives the tunnel one, and if
that token could edit Access, a compromised CI could take itself out
from behind Access.

### The ArgoCD admin password

Since 2026-08-12 it lives in the store, encrypted with the age key —
there is no need to write it down separately (principle D11: the
operator safeguards the age key and nothing else). To read it:

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/aegis.key
sops -d --input-type binary --output-type binary \
  "$AEGIS_HOME/.state-secrets/argocd_admin_pass.enc"
```

`argocd-initial-admin-secret` no longer exists: it was deleted on
rotation, which is what ArgoCD expects you to do and nobody did.

### The backups: two halves and a separate disk

There are TWO and you need both. `aegis state backup` brings the
platform's STATE; `aegis data backup` brings the tenants' DATA. With
the state alone you raise an empty platform; with the data alone you
have a dump and nowhere to put it.

```bash
export AEGIS_BACKUPS=/path/on/ANOTHER/disk/aegis-backups

aegis state backup                          # the state -> platform/
aegis data backup                           # the data -> one per organization
aegis data list    <bundle.age>
aegis data restore <bundle.age> --org <org>
```

The tree they produce:

```
$AEGIS_BACKUPS/
  .aegis-destino                     the filesystem's UUID, written down
  platform/aegis-state-<ts>.age
  org-<name>/aegis-datos-org-<name>-<ts>.age
```

Three things worth knowing, and all three were born from a failure
that does not announce itself:

- **One bundle per organization.** Restoring one does not force you
  to open the others' safeguard —which carries third-party data—
  and the question `aegis check` answers stops being "is there a
  backup?" and becomes "does EVERY organization have a backup?". It
  enumerates them from the contracts: an organization that declares
  data and has no bundle is a FAILURE, not a silence.
- **The destination goes on ANOTHER disk**, and the first capture
  writes its filesystem's UUID into `.aegis-destino`. If it does not
  match, nothing is written. Without that guard, a second disk that
  the desktop mounts at login —that is, not mounted during boot—
  leaves the path as an empty directory on the root disk, and the
  backup lands there: success reported, zero protection, and the
  copy that was supposed to survive the disk living on the disk.
- **`AEGIS_BACKUP_SINK`** takes the bundle off the machine. As long
  as it is not configured, the check warns on every round, and it is
  right.

#### The encryption, and the only way to lose all of this

Both bundles are **`age` files**. They are encrypted with aegis'
PUBLIC key and opened with the private one, the same
`~/.config/sops/age/aegis.key` that SOPS uses for the repo's `.enc`
files. One single pair for both things: there is no second key to
administer.

Encrypting does not need the private half. `aegis data backup`
derives the public key from whichever key you have at hand (or reads
it from `AGE_PUBLIC` / `$AEGIS_HOME/.age-public`), so a machine can
back up without being able to read what it backed up.

**The age key NEVER enters a bundle.** Both tools check this before
encrypting and ABORT if they find key material inside; check 080 of
`aegis verify` demands it. The reason is the obvious one: the egg and
the hen in the same basket protect nothing. The consequence is
equally obvious and has to be said out loud:

> **If you lose the age key, every `.age` on that disk is a brick.**
> There is no recovery, not partial, not by brute force, and we do
> not have it either. The key is THE irreducible: it goes to your
> offline safeguard, and that is a different place from the backup
> disk — if they live together, a single accident takes both halves.

And why the encryption is not ceremony: the state bundle carries the
tunnel's `terraform.tfstate` **with the `tunnel_token` in the
clear**. There is no second layer there; the bundle's `age` *is*
what protects it.

**Opening one without the tool.** This is what matters in the
scenario a backup exists for: a disk plugged into another machine,
with no repo and no aegis. `age` and `tar` are enough, and they
produce SQL and plain files:

```bash
age -d -i ~/.config/sops/age/aegis.key <bundle>.age | tar -xzvf -
```

`aegis data list` / `aegis data restore` are convenience — they
validate the manifest, compare credentials, restore into the right
database — not a proprietary format. Verified on 2026-08-22 against
a real bundle.

**And it is verified at the moment of writing it.** Both tools do a
ROUNDTRIP: they decrypt the freshly created bundle with the private
key and compare it byte for byte against what they captured. Without
that you have «backups»; with it, proven restoration — which is what
Law 21.719 demands and what you want on the day you need it. If the
private key is not there, the bundle is produced anyway but marked
NOT-VERIFIED, loudly.

Warnings:

- Rotating `cosign_key` invalidates ALL issued signatures →
  protocol `platform/docs/protocols/issue-cosign-keypair.md` §5
  (re-signing what is deployed). The tool already refuses it; do not
  force it by another route.
- Re-running a phase does NOT rotate a secret by itself (the store
  restores the old `.enc`): to rotate = `aegis rotate run --yes`
  FIRST, then the phase. Checklist:
  `platform/docs/protocols/rotation-checklist.md`.
- `aegis destroy --yes` is also the "dirty cloud" cleanup before a
  new run.

## 7. When to stop and escalate to the operator

- Any irreversible action: deleting external resources (webhooks,
  DNS, repos), `aegis destroy --yes`, rotating irreducibles.
- Anything that requires seeing secret material in the clear.
- Your hypothesis contradicts the operator's evidence → stop and
  show the data (historically: 2 times the operator refuted the
  agent's diagnosis with evidence; both times he was right).
- The cluster ended up in a state the init does not contemplate
  (e.g. a poisoned auto-sync, "will not retry") → do NOT improvise
  surgery; the answer may be a clean snapshot + re-init, and that
  decision belongs to the operator.

When closing an operating session with findings: leave the evidence
(gates.jsonl, relevant logs, commands executed) in a file for the
operator — the post-mortem cannot depend on somebody having read the
screen.

---

*Last updated: 2026-07-24, at the close of VERSION 2. Translated to
English and brought to the v3 command surface on 2026-08-24.*
