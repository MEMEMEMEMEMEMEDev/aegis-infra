# Changelog

Nothing here is a promise of a version: `main` is what you clone. This
file says what changed for whoever installs or operates, from which
commit, and what it asks of an instance that already exists.

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
- **The AI gateway starts with an empty task registry** (`ai-gateway`
  commit `844c079`): a platform is born before its tenants.

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
