# Changelog

Nothing here is a promise of a version: `main` is what you clone. This
file says what changed for whoever installs or operates, from which
commit, and what it asks of an instance that already exists.

## 2026-09-25 — a release does not drop the people on the site

- **The canary and every app template that serves a port wait 5 s in
  `preStop` before stopping** (native `sleep` action: the runtime images
  carry no shell), with `terminationGracePeriodSeconds: 30`. On SIGTERM a
  pod leaves the endpoints and stops at the same instant, and traefik
  keeps routing to it until the change reaches it: measured 2026-09-24,
  every rollout under 300 req/s dropped ~296 requests in 3 s (cloud
  instance) and 295 (Debian). The worker template has no port and is
  unchanged. Check 245.
- **Apps created before this** keep their own `k8s/` (the template is
  copied once): add the same `lifecycle.preStop.sleep` to their
  Deployment; `aegis seed apply k8s/…` does not reach a tenant's repo.
  The canary: its Deployment lives in the canary's app repo, not in the
  platform repo — copy the block there.

## 2026-09-25 — the rate limit counts per visitor, and traefik has room

- **Every rate limiter now counts per VISITOR behind the tunnel.** A
  traefik rateLimit with no `sourceCriterion` counts by the connection, and
  behind Cloudflare every connection is cloudflared's: «50 req/s per
  visitor» was 50 for the whole internet. Measured with a control on
  2026-09-24: a quiet visitor at ~5 req/s got 197 × 429 of 300 while another
  IP pushed 80 req/s, and none alone. The generator's `<org>-ritmo` and the
  seed's `canary-ritmo` and `ntfy-ritmo` now scan X-Forwarded-For from the
  right, skipping the pod range the entrypoints trust (`10.42.0.0/16`).
- **traefik runs two replicas with 512Mi** (it was one with 256Mi, and was
  OOMKilled at ~1600 req/s towards a CPU-throttled backend). Check 244.
- **If your instance is live**: `aegis seed apply
  k8s/base/ingress/traefik/values.yaml
  k8s/organizations/org-canary/routes.yaml
  k8s/base/observability/routes.yaml --yes`, push, and re-render every
  organization's routes with `aegis org apply orgs/<org>.yaml` (the
  generator writes the new criterion into each `<org>-ritmo`).

## 2026-09-24 — the canary sync ArgoCD does not retry

- **Phase 80 re-fires the canary sync that died on the signed digest.**
  ArgoCD re-attempts an automated sync only for a new revision. On the
  second cloud VM the canary revision carrying the signed digest was
  synced while Kyverno could not verify signatures, and was denied; once
  Kyverno was repaired the canary gate waited fifteen minutes for a sync
  that never came. After the policy is live and before that gate, the
  phase now syncs the canary again when its last operation Failed
  refusing that exact digest; any other failure is left to the wait and
  its diagnostic. Check 237.

## 2026-09-24 — a Kyverno restart owed for the CA is measured

- **Phase 80 restarts Kyverno whenever a controller is older than its
  CA, not only on the run that injected it.** The registry CA reaches
  Kyverno by subPath, which never refreshes; the restart used to hang on
  a flag of the injecting run. On the second cloud VM that run died in
  mirror-images before the restart, every later run found the CA already
  in git, and the admission controller kept a CA file without the aegis
  CA: it fell back to plain HTTP against the registry and denied the
  signed canary (`GET http://…:5000/v2/: 400`). The phase now compares
  each controller's oldest running pod with the last write of the CA
  ConfigMap it mounts, restarts on any debt, and gates
  `kyverno-ca-cargada` afterwards. Check 236.
- **If your Kyverno denies signed images with that 400**: resume phase
  80, or restart its controllers by hand
  (`kubectl -n kyverno rollout restart deploy`).

## 2026-09-24 — aegis-base-nginx declares /tmp writable

- **The nginx base starts under its own smoke test.** Its `nginx.conf`
  puts the pid and every temp path under `/tmp` (tenant pods run with a
  read-only root), and its `runtime-test.yaml` declared only
  `/var/cache/nginx` and `/run`. Since the smoke test arrived
  (2026-09-20) every clean install died in phase 80 on
  `open() "/tmp/nginx.pid" failed (30: Read-only file system)`, and `php`,
  built on top of it, fell with it. The runtime test now names `/tmp`,
  as php's already did. Check 235 reads every `pid` and `*_temp_path`
  of each base's nginx.conf against what its runtime test mounts.
- **If your instance's consumers of aegis-base-nginx do not mount /tmp
  as an emptyDir**, they die the same way on the next base rebuild:
  the runtime test is the base's contract with them.
- **If your instance was installed before 2026-09-20**, bring the file
  over: `aegis seed apply base-images/nginx/runtime-test.yaml --yes`.

## 2026-09-24 — redis 8.6.7 and postgres 17.11: the next patch, not a wait

- **The seed pins the patch that followed.** `redis:8.6.4-alpine` and
  `postgres:17.10-alpine` carry util-linux with CVE-2026-53612 (HIGH,
  fixed) and upstream never rebuilds an old patch tag: it publishes the
  next one. `redis:8.6.7-alpine` and `postgres:17.11-alpine` (both built
  2026-09-21, same major) carry the fixed util-linux and OpenSSL 3.5.8.
  No exception was written: the packages ARE in those images (`setpriv`,
  `libuuid`), and the clean patch exists.
- **If your instance runs these images**: `aegis seed apply
  mirror-images/images.txt --yes`, push the commit, and run the
  `mirror-images` job. The service catalogue's digests follow in a
  separate commit, read off the live registry once the mirror publishes.

## 2026-09-23 — the dirty-cloud pre-check sweeps Access too

- **Reinstalling against the same zone no longer dies on 409
  `application_already_exists`.** Phase 25 already swept a previous
  instance's tunnel and CNAMEs by name; the second cloud VM (the first
  one's host froze) then hit five 409s in the apply, because the dead
  instance's Access applications carry the same domains, and its
  reusable policies and service token sat next to them under the same
  names. The pre-check now lists the account's Access applications
  (domains under `ROOT_DOMAIN`), policies and service token (the module's
  names), keeps whatever THIS instance's encrypted state owns, and
  deletes the rest under the same RED confirmation — apps first, since
  a policy in use refuses to die. Gate `access-sin-restos`, declared
  subjectless on `EDGE=local` and when the token cannot list. Check 234.
- **A live instance needs nothing.** Its own resources are in its state
  and are never touched; a re-run of phase 25 lists nothing to sweep.

## 2026-09-23 — the GPU device plugin lands only where the node says there is a card

- **The NVIDIA device plugin no longer tries to start on a node without a
  GPU.** Its DaemonSet is part of the core and is synced on every
  instance, but its pods need the `nvidia` runtime class: on an `AI=no`
  install the pod sat in `ContainerCreating` for hours and the ArgoCD app
  `gpu` never left `Progressing`. The DaemonSet now selects nodes
  labelled `aegis.dev/gpu=true`; phase 20 puts that label on the node
  under `AI=gpu` and measures it (`gpu-node-labelled`), and removes it
  otherwise. Check 233.
- **If your instance runs `AI=gpu` today**: label the node BEFORE this
  change reaches it through `aegis seed apply`, or the plugin is left
  with no node to land on:
  `kubectl label node --all --overwrite aegis.dev/gpu=true`. An `AI=no`
  instance needs nothing: the stuck pod disappears on the next sync.

## 2026-09-23 — cleaning the cloud cleans the encrypted state too

- **Phase 25 no longer resurrects a tunnel it just deleted.** When it
  finds the leftovers of a failed apply in Cloudflare, it deletes them and
  purged the local tfstate; since the state lives encrypted, the wrapper
  decrypted the deleted tunnel right back and the apply died on a 404
  three runs in a row. The tunnel module is now dropped from the state
  through the wrapper (the Access resources, still in the cloud, stay),
  the plaintext copies `tofu state rm` writes are shredded, and the
  seed's `.gitignore` covers them (`*.tfstate.*.backup`). Check 232.
- **If your instance is stuck on that 404**: `tofu-apply.sh
  -chdir=envs/cloudflare-tunnel state rm <each module.tunnel.* resource>`
  with `SOPS_AGE_KEY_FILE` exported, shred the `terraform.tfstate.*.backup`
  copies, then `aegis init --from 25`.

## 2026-09-22 — Zero Trust dormant, found before the edge is built

- **Phase 25 asks whether Cloudflare Access is enabled** before it
  creates a tunnel, a DNS record or a policy. A brand new Cloudflare
  account has Zero Trust dormant and answers 403 «not_enabled» to every
  Access call; the first cloud instance found out in the middle of `tofu
  apply`. The refusal names the page that switches it on, and both
  READMEs and the journey now say it belongs in the preparation.

## 2026-09-22 — the valve's probe can say yes

- **Phase 20 no longer withdraws a reservation that was working.** The
  valve that rolls the node's memory reservation back asks the API with
  `kubectl`, and the user's kubeconfig is written further down in the
  same phase: up there kubectl talks to localhost:8080 and refuses
  however healthy the cluster is. On the first cloud instance the API
  had been serving for three minutes while the probe kept saying no. The
  probe now uses k3s's own kubeconfig, with the user's as a fallback, and
  check 230 drives it against a healthy cluster, a dead one, and a
  machine where `sudo -n` is refused.

## 2026-09-22 — the owner's deploy-key policy, asked in time

- **Phase 00 asks whether the GitHub owner allows deploy keys.** An
  organization forbids them by default, and aegis asked for its first
  one in phase 15 — with two repositories created, two Cloudflare tokens
  minted and half an hour gone. The first cloud instance of the lab died
  exactly there («Deploy keys are disabled for this repository»). Now the
  run stops before it touches anything, naming the page that changes the
  policy. A personal account has no such policy and is left alone; an API
  that cannot answer is NOT measured, not refused.
- **The clocks' gate converges before it measures.** `enable --now` on a
  machine past the timers' `OnBootSec` fires them that second, and a
  timer whose service is still running has no next elapse yet. The gate
  now waits for one (up to two minutes) instead of failing a healthy
  machine.

## 2026-09-22 — a server image is not a desktop

- **`aegis host` no longer reserves memory for a desktop that does not
  exist.** It took `graphical.target` alone as proof that a human shares
  the machine, and cloud images boot into it with nothing graphical
  installed (the first Vultr VM of the lab: Ubuntu 26.04, no gdm, sddm
  or lightdm). Now a machine is shared when a display manager is
  installed or a local session holds a seat; an unreadable display
  manager still counts as shared. An instance already installed on a
  VPS keeps the floor it derived: `aegis host floor --set` changes it.

## 2026-09-22 — a machine aegis cannot install on is refused first

- **The host is the first question**, in `aegis preflight` (before its
  first `sudo`), in `aegis init` (before the phase loop, so `--from` and
  `--only` cannot walk around it) and at the top of phase 00 (before the
  wizard). The rule is Ubuntu 24.04 or newer, the same one the phase 20
  playbook asserts, and it lives in `lib/host.sh`. Until today the only
  refusal was that playbook: on a CachyOS machine the preflight had
  already written a sudoers drop-in and switched IPv6 off, the wizard had
  asked every question, and phase 00 had only warned.
- **If you ran aegis on another distribution before this commit**, what
  it may have left: `/etc/sudoers.d/010-aegis-init-nopasswd`,
  `/etc/sysctl.d/99-disable-ipv6.conf` (plus IPv6 off until reboot or
  `sysctl -w`), `/usr/local/bin/k3s*` (remove with
  `k3s-uninstall.sh`), `~/aegis/`, the age key in
  `~/.config/sops/age/aegis.key`; outside the machine, two GitHub
  repositories with the topic `aegis-v2-disposable` and, with
  `cloudflare`, API tokens whose names start with `aegis`.

## 2026-09-21 — the front page, and main under CI

- **Both READMEs rewritten as one document in two languages**, section
  for section: what you get, before you start, install, your first
  application, how it works, the console, the commands, where it has
  been run, what is not there yet. The English page had aged in silence
  (136 checks, fifteen phases, a `restore` that left the bucket behind);
  check 180 now reads both gap lists and knows that `aegis seed apply`
  exists. Every picture ships in both languages (`docs/assets/*.en.svg`),
  and the console appears as it is: two screens drawn from the shipped
  case corpus, and its four states.
- **`main` is verified by GitHub on every push** and the badge on the
  front page says so. The first run went red on check 117: on a CI
  platform the login (`runner`) is the platform's, not a person's; the
  people there are the pusher and the repository's owner, and the owner
  is now measured on every machine, from the origin of the clone.

## 2026-09-20 — a version another person can install

For a fresh install (`docs/journeys/your-machine.md`):

- **Phase 00 asks the GPU** when `AI=gpu`: `nvidia-smi` has to answer
  with VRAM before a phase runs; the gate names the driver's install
  path and the fallen-off-the-bus signature.
- **Phase 05 installs the three user clocks** (backup, host metrics,
  update notice), derives `backup.env`, enables linger, links
  `/usr/local/share/aegis`, and gates on a **next run** — not on
  «enabled». `aegis-backup.timer` carries `OnCalendar=daily` beside its
  interval, so a restarted timer never sits without an appointment.
- **The AI gateway starts with an empty task registry** (in `ai-gateway`
  since 2026-09-02): a platform is born before its tenants. Not new in
  this version; named here because a clone that is behind still refuses.

For the bases you own (`base-images/`):

- **`MEMBERS` is never empty** and **`PROPAGATE` is false unless asked**:
  a pipeline cannot know who fired it, so the caller says both.
  `aegis ci build base-images --members <m>` builds, scans, signs and
  tells nobody; `--propagate` rewrites the consumers, once, when you
  mean it. `image-watch` and phase 80 pass both.
- **Every candidate runs as a pod before it is signed**, under exactly a
  tenant's restrictions (non-root, seccomp, no capabilities, read-only
  root), with what the member declares in `runtime-test.yaml`. A base
  that does not come up is pushed and NOT signed: inert for every tenant.
- `BasePropagationStorm`: a consumer rewritten more than three times in
  a week for one base is somebody iterating with `PROPAGATE=true`.
- Check 036 weighs `requests` as well as `limits`, every sidecar, and
  every spelling of a pod's resources.

For an instance that already exists:

- **`aegis seed diff` / `aegis seed apply`**: what the seed changed that
  your instance lacks, told apart from what is yours (contracts, plans,
  secrets, derived blocks) and from what only moved in pins; brought
  over with your pins and blocks kept, in a commit you read and push.
- **`aegis check` exits 2** when a measure could not be taken, and 2
  dominates 1; it also asks the cluster for every contract's AppProject.
- `aegis state restore --force` is a flag wherever it stands; `aegis
  rotate --help` prints its usage.

For the product: `.github/workflows/verify.yml` runs the whole static
suite on every push and the teeth of every check a pull request
touches; gitleaks scans every push.

Checks 223 to 226, each with its teeth. Registro: plan 18.
