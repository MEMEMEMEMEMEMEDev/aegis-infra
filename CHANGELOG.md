# Changelog

Nothing here is a promise of a version: `main` is what you clone. This
file says what changed for whoever installs or operates, from which
commit, and what it asks of an instance that already exists.

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
