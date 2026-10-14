# How aegis works, in depth

This is the long version of the front page: the shape of the product, the
sixteen phases, what GitOps holds, how a push becomes a signed image, what
a tenant can and cannot do, how secrets and backups are handled, and how
the product verifies itself. Every number here is read from the tree, not
remembered; the commands that recompute them are at the end.

If you want to install it, start at `docs/journeys/your-machine.md`. If
you operate an instance, `docs/OPERATE.md`. If you change the product,
`docs/AGENTS.md` and `docs/glossary.md` are binding.

---

## 1. The shape: a product and an instance

aegis is split in two, and the split is the first design decision.

| | **the product** | **the instance** |
|---|---|---|
| what | this repository: `bin/ libexec/ lib/ init/ verify/ seed/ share/ docs/` | one machine's living state: `aegis.conf`, `platform/`, `.init-state/`, `.state-secrets/` |
| where | wherever you cloned it (`AEGIS_ROOT`) | `~/aegis` by default (`AEGIS_HOME`) |
| during a run | **read-only** | mutable |
| disposable | never | by design |

Where each thing lives is decided in exactly one place, twice: `lib/paths.sh`
for the bash commands and `lib/aegis/paths.py` for the python ones, both
reading the same environment variables, so two commands sitting side by
side cannot disagree about where the instance is.

The instance's `platform/` is a git repository on GitHub, instantiated from
`seed/platform/` by the init. The rule is structural: **what does not ship
in `seed/` did not ship.** When the product changes, `git pull` brings the
fix to the machine and `aegis seed diff` / `aegis seed apply` bring it to
the instance, keeping the instance's pins and derived blocks.

### The three outcomes, and a fourth

Every command, gate and check resolves to one of three outcomes, and says
which:

| outcome | rc | means |
|---|---|---|
| done / already | 0 | it was made so, or it was already so |
| wrong | 1 | it is missing, or it is not as declared |
| not-evaluable | 2 | **the instrument never reached the subject.** Not a pass, not a failure. |
| — | 3 | invalid usage, or a bug in the verifier itself |

The whole project exists because a fourth possibility, silence, used to be
indistinguishable from success. «I could not measure» outweighs «it is
wrong», because a wrong answer sends you to fix something and a silent
non-measurement sends you nowhere.

### The commands

`bin/aegis` is a dispatcher: `aegis <command>` executes `libexec/aegis-<command>`
and hands it everything else. The menu is derived from each command's
metadata, not maintained by hand, and a command without metadata does not
appear in the menu *and* turns the verifier red. Fifteen commands are bash,
seventeen are python; two (`aegis dev`, `aegis vps`) are hidden maintainer
tools. `aegis --help` prints the menu and `aegis <command> --help` the
detail of each.

---

## 2. The sixteen phases

`aegis init` runs the phases of `init/phases/` in order. Each phase is
idempotent, leaves a marker in `.init-state/` when it completes, and records
every **gate** (a measured assertion) as one line of `.init-state/gates.jsonl`:
time, phase, gate, result (`pass`, `fail`, `not-evaluated`) and duration.
A run with `aegis init-log` also keeps a **dossier**: the whole log and the
gates of that run under `.init-state/runs/`.

| phase | what it does | what proves it |
|---|---|---|
| `00-preflight` | Measures the host (distribution, sudo, disk, clock, DNS, the GPU when `AI=gpu`), runs the wizard when there is no `aegis.conf`, and aborts here rather than halfway through the cluster. | every gate green |
| `05-host` | Installs the pinned userland (tofu, sops, age, kubectl, helm, cosign, direnv, jq, git), each binary checked against the SHA-256 its publisher publishes, and the three user clocks (backup, host metrics, update notice). | `systemctl --user list-timers 'aegis-*'` shows three timers |
| `10-age-ceremony` | Generates the age key, the one root of trust; validates it by encrypting and decrypting a canary for real; demands a backup the operator proves by pasting it back; writes `.sops.yaml`. The only phase that shows a secret, and it shows it in a tmpfs file to be read from another terminal, never in the pane. | the operator's copy decrypts the canary |
| `12-workrepos` | Creates and seeds the two GitHub repositories the init owns (platform and canary), marked with a topic so a re-run reuses them. | `gh repo view` |
| `15-third-parties` | Mints the third-party credentials without a browser: deploy keys, the two webhook HMACs, the CI credential, and under `cloudflare` the scoped tokens from one ephemeral master credential that lives in tmpfs for the length of the phase. Everything it produces is encrypted into the platform repo and the store. | each credential proved against its consumer |
| `20-k3s` | Prepares the kernel and installs the pinned k3s with Ansible, without the bundled traefik and servicelb; writes the kubelet's eviction thresholds and the host's memory reservation; verifies the kubeconfig. | `kubectl get nodes` Ready |
| `25-edge-tofu` | Raises the edge. `cloudflare`: tunnel, DNS and Access through OpenTofu, the state encrypted with age. `local`: a systemd socket bridge on the host that hands ports 80 and 443 to traefik's fixed ClusterIP. | the hostnames resolve and answer |
| `30-argocd` | The one imperative install: the bootstrap Secrets through kubectl (the age key for KSOPS, the redis password, the admin password from the store) and `helm install` with the same values the Application will own. | ArgoCD answers |
| `35-gitops` | Hands control to git: AppProjects, the root App-of-Apps and the first syncs in order (cert-manager → the internal CA → issuers → traefik → argocd-secrets → argocd → the edge TLS → cloudflared). | Applications Synced; an end-to-end edge gate |
| `40-registry-pki` | The internal image registry with its own PKI and TLS from day one; the registry credential derived once into its consumers (htpasswd, pull secrets, netrc) in one process. | a push and a pull |
| `50-jenkins` | Jenkins with a random admin password and jobs defined in code from the first boot; ends with the CI tooling images built and published. | the first green build |
| `60-webhook` | Proves end to end that a push reaches Jenkins, one gate per link: the hook exists, GitHub delivers, Jenkins accepts the signature, a build appears. | a delivery with a 2xx and a build |
| `70-deploy-auto` | The canary's automatic deployment: the pipeline writes the digest, ArgoCD deploys. Before that it proves a commit that only touches manifests does not trigger a build (the anti-loop). | the canary serves |
| `80-supply-chain` | The trivy server, the cosign key, the mirror of pinned upstream images, the platform's own base images (each run as a pod under tenant restrictions before it is signed), and Kyverno's signature policy switched to Enforce **last**, when a signed image already exists to admit. | an unsigned image refused citing the policy; a signed one admitted |
| `85-observability` | VictoriaMetrics, vmalert, Grafana, VictoriaLogs, Vector, blackbox probes, Alertmanager and ntfy, with a heartbeat that reaches the phone: if the platform stops saying it is alive, that is itself an alert. | the heartbeat arrives |
| `87-ai` | The AI subsystem, if asked for: `AI=no` skips it and says so; `AI=cpu` raises the gateway, the controller and a small engine; `AI=gpu` measures the driver and the runtime first. Engines are born switched off. | the engines reach zero when the mode is closed |

**Resuming.** When a phase fails the init stops there, prints the absolute
command to resume with, and leaves its gates recorded. `aegis init --from NN`
re-runs the named phase (even if it has a marker: asking for a phase is
asking for it to run) and respects the markers of the later ones;
`--only NN` repeats one; `--reset-state` archives the gates and forgets the
markers. The phases re-derive their environment from disk before each
step, so nothing depends on an export of a previous phase.

**Order as mechanism.** There are no sync waves: the init decides the
when of each Application, every `*-secrets` App before its consumer, and
the admission policy goes last because an Enforce policy with no prior
signature would reject the platform itself.

---

## 3. What GitOps holds

The platform repo is an App-of-Apps. `k8s/argocd-apps/root.yaml` is synced
by hand (never by itself) and declares the groups; the seed declares
**31 Applications** in all:

| group | Applications |
|---|---|
| core | argocd-secrets, argocd (chart), cert-manager (chart), aegis-ca-issuer, cert-manager-issuers, traefik (chart), edge-tls, cloudflare-tunnel, gpu, ai-system |
| ci, supply chain and tenants | registry, vuln-policy, jenkins-secrets, jenkins (chart), trivy-system, trivy-server (chart), kyverno-base, kyverno (chart), kyverno-policies, org-canary, and one `org-<name>` per organization |
| observability | observability-base, vmsingle, vmagent, vmalert, vlogs, vlogs-events, vector, grafana (charts) |
| data | garage |
| the tenants' own | one Application per service repository, in the organization's project |

Charts are pinned by version in the Applications; everything else is
plain manifests under `k8s/base/`, rendered with kustomize. Secrets are
never in git in the clear: each `*-secrets` directory lists its encrypted
files in a KSOPS generator, and ArgoCD's repo-server decrypts them with
the instance's age key at render time.

**AppProjects** are the boundary, applied with kubectl before root so no
Application can edit them: `aegis-bootstrap` (root may only create
Applications), `aegis-platform` (the platform plane, cluster-wide),
`aegis-organizaciones` (each organization's substrate from the platform
repo), and one `aegis-tenant-<org>` per organization, derived from its
contract: only its repositories, only its namespace, nothing
cluster-scoped, and a blacklist of the kinds the platform writes for it
(quota, limits, the Kyverno sizing policy, RBAC, routing, middlewares).

---

## 4. The supply chain, in detail

A push to an application repository goes through six links, and each link
is measured by `aegis builds` and drawn on the console's Deployments screen.

1. **The push reaches Jenkins** through a webhook signed with an HMAC the
   init generated (under `local`, where GitHub cannot reach the host,
   Jenkins polls instead). A multibranch job per repository, defined in
   code; every branch builds, scans and signs, only `main` deploys.
2. **kaniko builds the image** in an unprivileged pod, to a tar, without
   pushing yet. The `FROM` of the application's Containerfile must be one
   of the platform's own bases, by digest; a guard refuses anything else.
3. **trivy scans the tar** against the trivy server. Findings are split by
   layer: what lives in the base's layers is the platform's (judged at the
   mirror's door, re-scanned every morning), what lives in the image's own
   layers is judged by `vuln-policy/verdict.sh` against what runs today.
   A new fixable CRITICAL or HIGH that the change brings stops the build;
   what was already running becomes **debt with a date** (15 days for a
   critical, 30 for a high, measured from the CVE's publication); a CVE on
   CISA's exploited-in-the-wild list has no window at all.
4. **crane pushes** the already-scanned tar to the internal registry and
   reads its digest.
5. **cosign signs by digest**, never by tag, with the instance's key,
   without uploading anything to the public transparency log.
6. **The pipeline writes the digest** into the kustomize overlay of the
   repository and commits it; ArgoCD sees the commit and deploys.
   **Kyverno**, in Enforce with `failurePolicy: Fail`, admits in a tenant
   namespace only pods whose every image (containers, init containers,
   ephemeral containers) carries a valid signature by the platform's key,
   and mutates the reference to the digest.

The platform's own images follow the same discipline with three jobs:
`mirror-images` brings upstream images in by pinned tag *and* digest and
judges them with the same verdict; `base-images` builds the bases aegis
owns (nginx, node, php), runs each one as a pod under a tenant's
restrictions before signing it, and propagates its digest into every
consumer `FROM` when told to; `image-watch` re-scans everything that is
served and everything that runs in the tenants every morning and keeps
the books (`image-watch/ledger.txt`, committed to the platform repo) that
`aegis vulns`, `aegis check` and the console read. The alerts are a
ladder: `VulnDebt` once a day, `VulnDebtDueSoon`, `VulnDebtOverdue`,
`VulnExploited`.

---

## 5. The tenancy model, honestly

One YAML per organization, `orgs/<name>.yaml`, is the contract. Its keys are
Spanish on purpose (they are the one vocabulary an app team writes):
`organizacion`, `dominio`, `cuota` (a plan name: `pequena`, `mediana`,
`grande`, never numbers), `servicios` (six kinds: `estatico`, `http`,
`worker` from the tenant's repository; `postgres`, `mongodb`, `redis`
provided by the platform), `almacenamiento` (a bucket in Garage), `usa`
(what a service may reach: `internet`, `postgres`, `redis`, `mongodb`,
`bucket`, `ai`), `secretos` (credentials the platform cannot invent),
`gpu: true` (one service may be handed the instance's card), `ai` (a plan
against the AI gateway).

`aegis org apply` derives from it, in marked blocks rewritten whole:

| derived | what it holds |
|---|---|
| Namespace | labelled `aegis.dev/part-of: aegis-tenants` and `pod-security.kubernetes.io/enforce: restricted`; `aegis.dev/gpu-otorgada` when granted |
| ResourceQuota and LimitRange | the plan's numbers from `plans.yaml` (cpu, memory, pods, volumes, storage) |
| a Kyverno `Policy` in the namespace | each service's size (`tamano: chico`, `mediano`, `grande`) written into its pods, so a repo cannot grow its own limits |
| NetworkPolicies | default-deny in and out; DNS; the edge in; exactly what `usa:` names out |
| RBAC | the service accounts the pods run as, with no token mounted |
| routing | the IngressRoutes and the three middlewares (headers, per-visitor rate limit, body cap, plus the streaming sibling for SSE and WebSockets) derived from `dominio` and each `publico:` path; the repo cannot write its own |
| Jenkins jobs | one multibranch job per repository, in the platform's job-dsl block |
| ArgoCD | the organization's Application in `aegis-organizaciones` and one Application per service repository in `aegis-tenant-<org>` |
| secrets | the encrypted Secrets each service needs (`aegis secret create`), born in the platform repo under the organization |
| backups | the organization in the data bundle (`aegis data backup`) |

What a tenant **gets**: an isolated namespace with restricted pod
security, a closed network opened only where the contract says, a quota,
a pipeline that builds, scans, signs and deploys its pushes, public
hostnames with TLS, databases and a bucket on request, and a console that
measures all of it.

What a tenant **cannot** do from its repository: write its own routing or
middlewares, change its quota or its sizes, grant itself RBAC, reach the
cluster scope, run privileged, run an unsigned image, or choose the GPU
runtime (the platform writes `runtimeClassName: nvidia` and the card
request only for the one service a contract grants).

What this model is **for**: one team and its projects on one node. The
isolation holds between organizations in the cluster; everyone who can
push to an application repository is trusted by the platform. See the
front page's *What is not there yet* for what this means today.

---

## 6. Secrets

The rules are written down (`seed/platform/docs/conventions/secrets.md`)
and enforced by checks:

- **Never in argv.** `/proc/PID/cmdline` is public: values travel through
  files in tmpfs, stdin, `htpasswd -i`, `jq --rawfile`, curl config files.
- **Never printed.** Shape checks by length only (`wc -c`). The age key is
  shown once, in a tmpfs file read from another terminal, and never again.
- **Cleartext only in tmpfs** (`/dev/shm`), `umask 077`, shredded in the
  EXIT, INT and TERM traps.
- **Kubernetes Secrets by `data:`**, byte-preserving; never a `stringData`
  assembled by hand (YAML folding adds a byte and breaks an HMAC).
- **Encrypted at the repo path.** sops's creation rule matches by path, so
  a Secret is encrypted where it lives and the roundtrip is checked every
  time.
- **One origin per shared credential.** The registry password is derived
  into htpasswd, pull secrets and netrc in one process; the webhook HMAC
  into GitHub and the receiver's Secret in one commit.
- **The store.** Every secret the init generates is persisted encrypted
  with the age key in `.state-secrets/` and restored on re-runs instead of
  regenerated, so a resume never orphans a deploy key or a webhook. The
  store distinguishes «does not exist» (generate) from «does not decrypt»
  (stop: regenerating would desynchronise a third party).
- **The age key is the one irreducible.** It opens everything else; it is
  never in a bundle, never in a log, never in the repo. Lose it and every
  backup is a brick: the ceremony in phase 10 exists for that.

**Rotation.** `aegis rotate` knows every credential in the store: its
class (normal, delegated, irreducible), the phase that regenerates it, the
Application to sync, the verifier that proves it against its real consumer,
the third party involved and the blast radius. `aegis rotate check`
exercises each one without rotating it. Two are refused as irreducible,
each with its own protocol: the age key (`rotate-age-key.md`) and the
cosign keypair (rotating it invalidates every signature ever issued).

---

## 7. The two edges

| | `cloudflare` | `local` |
|---|---|---|
| needs | a zone in Cloudflare with Zero Trust switched on, the account and zone IDs, one master credential pasted once | nothing outside the machine |
| what phase 25 does | with OpenTofu: a tunnel, a CNAME per hostname, Access in front of the operator consoles; the state encrypted with age | four systemd units: a socket-activated proxy that hands ports 80 and 443 on the chosen address to traefik's fixed ClusterIP |
| TLS | Let's Encrypt through DNS-01 with a scoped token; Cloudflare terminates at the edge | the instance's own CA (the browser warns until you import it) |
| names | `argocd.`, `jenkins.`, `grafana.`, `ntfy.<domain>` and each organization's `dominio` | the same names, resolving to the host (sslip.io, or your `/etc/hosts`) |
| webhooks | GitHub delivers; phase 60 proves it | GitHub cannot reach the host; Jenkins polls and ArgoCD reconciles on its interval; the gates record «not evaluable» rather than pretending |
| the consoles | behind Cloudflare Access | on the host, reached from the host |

The seed is identical under both edges; the difference lives in the
phases. The operator console (`aegis console serve`) is never published
through either edge: it listens on loopback and is reached over an SSH
tunnel.

---

## 8. Observability and the alert ladder

VictoriaMetrics (vmsingle, vmagent, vmalert) for metrics and alerts,
VictoriaLogs with Vector for logs and Kubernetes events, Grafana with
seeded dashboards (platform, edge, supply chain, host, bootstrap, usage),
blackbox probes against every public hostname and the operator consoles,
Alertmanager with a bridge to ntfy so alerts reach a phone.

The design has two rules. **Absence is a signal**: for every measured
series there is a sibling alert that fires when the series stops arriving
(`BlackboxSinMedida`, `TrivyDBSinMedida`, `BackupMeasurementStopped`,
`MedicionDelAnfitrionAusente`…), and a dead-man heartbeat (`DeadmanAegis`)
that pages when the platform goes quiet. **A ladder, not a red light**:
vulnerability debt climbs from `VulnDebt` (once a day) to `VulnDebtDueSoon`,
`VulnDebtOverdue` and `VulnExploited`; backups from `BackupStale` to
`BackupNeverArrived`; the host from «the desktop was pushed to swap» to
«the node has no reservation for the host» and «the disk is about to fill».
The update window has its own rungs (`UpdateWindowDue`,
`UpdateWindowNeedsAHuman`, `UpdatePageLeftUp`).

`aegis check` is the round: every section of the live instance measured
against what is declared, in the four states, and it is what the console's
Health screen draws.

---

## 9. Backups: the machine and the tenants

Two halves, and a backup of one does not restore the other.

**`aegis state`** is the machine: the encrypted store, the phase markers
and the edge's encrypted tofu state, in one age-encrypted bundle whose
roundtrip is proven at capture. It refuses to include the age key.
`aegis state restore` into another instance directory proves the restore.

**`aegis data`** is the tenants: one bundle per organization with the
database roles and dumps, every object of its bucket with its sha256, and
a fingerprint of the live credential (never the credential). The internal
registry and the AI model volumes are not in it, on purpose: both are
reproducible from pins. `aegis data remote` sends bundles to an off-site
bucket (Cloudflare R2), keeps a cadence (`--set 6h`) that a user timer
enforces, and publishes the freshness of each copy as metrics the console
draws on Storage. A restore into another instance detects that the database
credential changed and refuses without `--force`.

---

## 10. The verifier

`aegis verify` measures the product without a cluster: **291 checks**, each
a file in `verify/checks/` with exactly one verdict (PASS, FAIL or SKIP),
run in both edge profiles. Silence is red: a check that emits no verdict
fails, and one that emits two is a bug in the verifier (rc 3). «Not
evaluable» is a third outcome with its own exit code.

Every check has its **tooth** in `verify/teeth/`: mutations of the tree
(`red_N`) that must turn the check red, and legitimate changes
(`control_N`) that must keep it green. The teeth runner copies the tree to
tmpfs, applies each mutation, reports a mutation that changed nothing as
INERT and one that could not be applied as BROKEN, and runs the check. A
check without a biting tooth does not count as a check. `aegis verify
--harness` tests the verifier itself. The whole suite in both profiles
runs in about three minutes.

CI (`.github/workflows/verify.yml`) runs the suite on every push and pull
request, the teeth of every check a pull request touches, and gitleaks over
the history. Nothing in CI talks to a cluster, a registry or a cloud.

Many checks are **executable specifications**: they drive a phase's block
under `set -euo pipefail` against fake binaries (a fake GitHub, a fake
tofu, a fake Jenkins, a real sops and age over a throwaway key) and assert
what the block says and does. Each check's header carries the bug and the
run that motivated it.

---

## 11. The host's budget

The platform does not take the whole machine. `plans.yaml` fixes the
**floor** for the host: 2 GiB on a dedicated box, 6 GiB (and 2 GiB of VRAM)
on a shared desktop, plus 2 GiB for the system and 500 MiB for the
kubelet's eviction margin; phase 20 writes that reservation into the
kubelet, and the host metrics watch it. `aegis host measure` writes down
what the machine has, `aegis host budget` says whether what the platform
reserves fits in what the machine leaves, `aegis host floor --set` moves the
desktop's floor, and `aegis capacity` says how many more organizations of
each plan would fit.

What the seed asks for, as a static sum of its manifests on 2026-10-13:

| AI lane | requests | limits |
|---|---|---|
| `no` / `cpu` | about 5.5 GiB | about 14 GiB |
| `gpu` | about 16.5 GiB (14.5 plus 2 of RAM-backed `/dev/shm` for the engines) | about 34 GiB |

Requests are what the scheduler reserves; limits are what the pods may
grow into. The published minimum is 25 GB free on `/` (`plans.yaml`,
enforced by the preflight); 8 GB of RAM starts the platform without AI and
without margin, 16 GB is what every documented run had. A 4-CPU node
admits one build at a time.

---

## 12. Versions, and where they are pinned

Every version is pinned where it is consumed, and `aegis update inventory`
reads them all and compares them with what exists upstream:

| what | where |
|---|---|
| k3s, the userland tools (tofu, sops, kubectl, helm, cosign) | `seed/platform/ansible/inventory/group_vars/all.yml` |
| the twelve charts | `targetRevision` in `k8s/argocd-apps/*.yaml`, echoed on the first line of each `values.yaml` |
| the upstream images the mirror admits | `seed/platform/mirror-images/images.txt`, by tag and digest |
| the platform's own bases | the Containerfiles under `base-images/`, propagated into every consumer `FROM` by digest |
| the CI tooling in the pipelines | the pod templates of the Jenkinsfiles |
| the Python side of Ansible | `seed/platform/ansible/requirements.txt` |

`aegis update plan` says what a maintenance window would raise, `aegis
update window` runs the protocol (dry by default), `aegis update rollback`
undoes it. The protocol is `seed/platform/docs/protocols/updates.md`.

---

## 13. Design limits

Said plainly, because the checks would say them anyway.

- **One node.** No high availability and no multi-cluster. It is a
  platform for one team and its projects, not for a fleet.
- **One repository per service.** A monorepo keeps its own Jenkinsfile and
  is not first class.
- **The trust model is a team's.** Isolation holds between organizations;
  it does not hold between an application repository and the platform.
  Whoever can push to an application repository is trusted by the whole
  platform. Closing that is the first item of the next release.
- **Kyverno reaches only registries the instance's CA signs.** A public
  image is refused with an `x509` error, not with «no signature».
- **The console is the operator's.** Loopback only, over SSH. The
  tenant's console does not exist.
- **Restoring between instances is not automatic.** A bundle is encrypted
  to the key of the instance that made it.
- **`amd64` only**, and Ubuntu 24.04 or newer on the host.

---

## The numbers, recomputed

```bash
ls verify/checks/[0-9]*.sh | wc -l                 # checks
ls verify/teeth/[0-9]*.sh | wc -l                  # teeth
ls init/phases/*.sh | wc -l                        # phases
ls libexec/aegis-* | wc -l                         # commands (two hidden)
ls -d seed/templates/*/ | wc -l                    # application templates
grep -rh '^kind: Application$' seed/platform/k8s | wc -l   # Applications the seed declares
grep -c '^## Disease' seed/platform/docs/failure-modes.md   # failure classes
```
