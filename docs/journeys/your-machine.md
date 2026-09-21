# Your machine — installing aegis with your own domain and your own GPU

> The journey of the second person to install aegis: a Linux box at
> home, a zone of your own in Cloudflare, an NVIDIA card, and the product
> cloned from `main`. Written on 2026-09-20, before that install ran; it
> is corrected by what the install finds, in this file, so read the log
> at the bottom.

This is the `cloudflare` profile with `AI=gpu`, and **it has never run
from zero on a machine that is not the author's**. The foreign-instance
rehearsal of 2026-08-27 was `EDGE=local` (see `foreign-instance.md`).
So this is a first run, and it is treated as one: you run it with a
dossier, you send what stops, and every stop is fixed in the product
and comes back to you as a `git pull` and an `aegis init --from <phase>`.
Nothing is fixed by hand on your machine if the class can be fixed in
the product.

## 1. What you need before you start

| thing | why |
|---|---|
| Ubuntu (24.04 or newer), a user with sudo, ~30 GB free on `/`, a GPU whose driver answers `nvidia-smi` | phase 00 measures all four and stops before anything runs if one is missing. The driver is the operating system's: `sudo ubuntu-drivers install`, reboot. |
| a zone in Cloudflare (`example.com` you control), its **Account ID** and **Zone ID** | the edge: a tunnel, DNS records, Access in front of the operator consoles. Both IDs are on the zone's overview page; they are not secrets. |
| a **Cloudflare master credential**, pasted ONCE in phase 15 and destroyed in tmpfs | the init mints its own scoped tokens from it (DNS, API, Access) so that nothing long-lived carries the master. Global API Key, or an account token with *Account API Tokens: Edit*. |
| `gh auth login` with `repo` and `delete_repo` | the init creates two repositories in your account (the platform repo and a canary app) and registers deploy keys and webhooks. There is no separate token: the init uses your `gh` session. |
| git identity (`git config --global user.name/email`) | every phase that changes the platform repo commits. |
| a USB stick (or two) for the age key | phase 10 generates the one key that opens everything and shows it once. You copy it to media you keep offline. Lose the key and every backup is a brick; there is no reset. |
| `tmux` | the init runs for a while and asks you two things. A dropped ssh session should not kill it. |

What you do **not** need: cosign keys, certificates, DNS records, the
tunnel, registry credentials, an R2 bucket. The init makes all of them.

## 2. The sequence

```bash
git clone <the repository this README came from> ~/aegis-infra   # main, no tag: it is what you clone
cd ~/aegis-infra && ./bin/aegis preflight        # repairs what it can; run it until it is all OK
gh auth login                                     # repo + delete_repo
tmux new -s aegis
aegis init --check                                # the wizard, then every gate in dry-run: nothing is changed yet
aegis init-log                                    # the real run, with a dossier in ~/aegis/.init-state/runs/
```

`aegis init --check` asks the sixteen questions of the wizard the first
time (`EDGE=cloudflare`, your domain, the two IDs, `AI=gpu`, the
maintenance hooks may stay empty) and then walks every phase without
acting. Read its output once: it is the list of what the real run will
do to your machine.

The real run has **two human moments** and no other:

1. **Phase 10, the age ceremony.** It shows the key once and waits until
   you have copied it to your media and pasted it back. Do this from a
   second tmux window; do not paste the key into anything that logs.
2. **Phase 15, the Cloudflare master.** Paste it once. It lives in
   `/dev/shm` for the length of the phase and is shredded at the end.

Everything else runs alone. The sixteen phases, in order, with what
each one proves:

| phase | what it does | what proves it |
|---|---|---|
| 00 preflight | measures the host, DNS, clock, sudo, disk, **the GPU** | every gate green |
| 05 host | installs the pinned userland (tofu, sops, age, kubectl, helm, cosign), each checked against its publisher's sha256; **installs the three user clocks** (backup, host metrics, update notice) | `systemctl --user list-timers 'aegis-*'` shows three timers with a NEXT |
| 10 age ceremony | the key, its offline copy, the platform repo seeded and rendered | the copy opens a test file |
| 12 work repos | your two GitHub repos, marked and pushed | `gh repo view` |
| 15 third parties | scoped Cloudflare tokens, deploy keys, webhooks, the R2 bucket for backups | each credential proved against its consumer |
| 20 k3s | the cluster, the NVIDIA runtime | `kubectl get nodes` Ready |
| 25 edge | the tunnel, DNS, Access, through tofu | your hostnames resolve |
| 30 argocd, 35 gitops | the one imperative install, then everything else from git | Applications Synced |
| 40 registry | the internal registry with TLS from day one | a push and a pull |
| 50 jenkins | the CI, jobs as code, the tooling image built | the first green build |
| 60 webhook | a push reaches Jenkins, end to end | a delivery with a 2xx |
| 70 deploy-auto | the canary tenant and the image updater | the canary serves |
| 80 supply chain | mirrors, **the bases aegis owns (each run as a pod before it is signed)**, cosign, Kyverno Enforce last | an unsigned image refused, a signed one admitted |
| 85 observability | metrics, logs, alerts, the heartbeat to your phone | the heartbeat arrives |
| 87 ai | the gateway, the engines on your card | the engines reach zero when the mode is closed (that is the proof) |

Then:

```bash
aegis check                     # the round: expect 0. A 2 means something could not be measured, and it says what
aegis verify --profile both     # the static suite over the product you installed
```

## 3. When something stops

Every stop prints its gate, its diagnosis and the command to look at.
Send three things and nothing else:

```bash
jq -r 'select(.result=="fail") | "\(.phase) \(.gate)"' ~/aegis/.init-state/gates.jsonl   # the line that failed
ls -t ~/aegis/.init-state/runs/ | head -1                                                # the dossier (the whole run)
aegis check --json > round.json                                                           # if the cluster is up
```

The fix lands in the product, you `git pull` in `~/aegis-infra`, and you
resume with `aegis init --from <phase>`. The phases are idempotent: a
phase that already passed is skipped, the named one re-runs.

Two stops this run is expected to meet, and what they mean:

- **`gpu-responde` red in phase 00**: `nvidia-smi` did not answer. The
  driver is not installed, or the card fell off the bus (`journalctl -k
  | grep Xid`). Install or reboot; the init waits for nothing.
- **`ai-gateway-responds` red in phase 87**: the gateway did not roll
  out. Its log says why. Until 2026-09-02 an instance with no
  organizations could not start it at all («registro sin tareas»); the
  gateway image you build carries that fix if the `ai-gateway` you build
  from is at or after the commit that accepted an empty registry
  (2026-09-02, «un sustrato sin inquilinos no es un archivo roto»).

## 4. After the install: your first organization, and a base of your own

```bash
cd ~/aegis/platform
aegis org schema                       # the contract's shape
$EDITOR orgs/mine.yaml                 # organizacion, dominio, cuota, servicios
aegis org validate orgs/mine.yaml
aegis secret create orgs/mine.yaml     # its encrypted secrets, born here
aegis org apply orgs/mine.yaml         # renders everything it derives; prints the one kubectl apply it does not do
git add -A && git commit -m "org: mine" && git push
kubectl apply -f k8s/bootstrap/appprojects-tenants.yaml   # the AppProject; aegis check tells you if it is missing
aegis app apply mine                   # the repo, its deploy key and its webhook, in GitHub
aegis sync root
```

And a base image for a language aegis does not ship yet (this is the
part that cost the author eight hours and 168 builds on 2026-09-13,
before the guards in this version):

```bash
mkdir base-images/ruby && $EDITOR base-images/ruby/Containerfile base-images/ruby/runtime-test.yaml
aegis ci build base-images --members ruby        # builds, scans, RUNS it as a pod under a tenant's restrictions, signs. Tells nobody.
# iterate until that is green — nothing else in your fleet notices
aegis ci build base-images --members ruby --propagate   # once: every consumer's FROM, one commit each
```

`MEMBERS` is never empty and `PROPAGATE` is off unless you say so
(check 223). A base that does not come up as a pod is not signed, and
an unsigned base is inert for every tenant.

## 5. When the product moves

You `git pull` in `~/aegis-infra`. That brings the fix to your machine;
it does not touch your instance's platform repo, which is yours. To see
what the seed changed that your instance does not have yet, and to
bring it over with your pins and your derived blocks kept:

```bash
aegis seed diff
aegis seed apply <path>... --yes     # a commit in your platform repo, for you to read and push
```

## 6. The log of this journey

_(written by the run; empty until it happens)_
