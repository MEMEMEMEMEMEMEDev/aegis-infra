# aegis

**You `git push`. Your server builds, scans, signs and publishes.**

[![verify](https://github.com/MEMEMEMEMEMEMEDev/aegis-infra/actions/workflows/verify.yml/badge.svg)](https://github.com/MEMEMEMEMEMEMEDev/aegis-infra/actions/workflows/verify.yml)
· Léelo en español: [README.md](README.md)

![A Linux machine and a GitHub account go in; your own deployment platform comes out](docs/assets/que-es.en.svg)

## In one sentence

aegis turns a Linux machine and a GitHub account into your own
deployment platform. It installs and wires together everything it takes
for a `git push` to end as an application published on the internet,
with a certificate, scanned and signed, and then it keeps watch that it
stays that way. It is free software, it runs on your server and the keys
are yours.

For whoever pushes, it feels like Vercel or Heroku. The difference is
that nobody else is inside.

## Who it is for

- **For whoever has a server and several applications.** A VPS, a
  machine at home, an old box running Linux. Today you publish by hand,
  copying files or starting containers one by one, and every change is
  an afternoon. With aegis, the change is a push.
- **For a small team that wants to work like the big ones without
  paying like the big ones.** Every project in its place, with its
  database, its domain and its backups, and one flow for all of them:
  push, build, test, publish.
- **For whoever does not want to hand over their keys.** Commercial
  platforms are comfortable because they keep your code, your secrets
  and your data. aegis gives you the same comfort on your machine: the
  code on your GitHub, the secrets encrypted on your disk, the data on
  your server.
- **For whoever wants to understand what runs.** Nothing is hidden.
  Every piece is a known tool, every decision is written down, and the
  platform measures itself every day and tells you what it found.

It is not for a company with dozens of teams, nor for hosting
strangers. It is for one team and its projects.

## What problem it solves

Building a platform like this by hand is a project of its own: a
cluster, continuous deployment, an image registry, a vulnerability
scanner, signatures, certificates, DNS, tunnels, metrics, logs, alerts
and backups. Each piece has its manual and its way of breaking, and
wiring them together is where the time goes. Most people leave it half
done: they publish without scanning, keep secrets in loose files, have
no tested backups, and never know something is wrong until a user says
so.

![By hand: ten pieces, each with its manual. With aegis: one command, then a push](docs/assets/antes-despues.en.svg)

aegis does that work once, with the pieces already chosen and already
wired, and with one rule that holds everywhere: **if something could not
be checked, it says so.** A platform that stays quiet when it does not
know is worse than one that does not exist.

## What it does

![What happens to a git push: build, scan, sign, deploy, expose; unsigned, refused](docs/assets/pipeline.en.svg)

- **Installs the whole platform with one command.** `aegis init` asks
  the little it cannot infer and walks through sixteen phases. Each
  phase records what it checked. If something fails, it stops there,
  says why, and can be resumed.
- **Turns every push into a release.** The application is built in an
  isolated environment, scanned for vulnerabilities, signed and
  deployed. It ends up published with TLS at `your-app.your-domain`,
  without you touching DNS or certificates.
- **Lets nothing run that did not go through there.** An unsigned image
  does not enter the cluster. The platform refuses it and says why.
- **Signs a project up with one file.** One contract per project says
  which services it has, which database, which domain and how much it
  may consume. Everything else is derived from it.
- **Watches itself.** Metrics, logs, a daily round of checks and alerts
  to your phone. Every morning it re-scans what runs and keeps a book of
  what must be fixed and by when.
- **Backs up and knows how to restore.** Each project's data and the
  platform's own state, encrypted, with the restore tested.

## Who does what

![The team pushes; the platform builds, scans, signs and publishes; you watch the console and get the alerts](docs/assets/quien-hace-que.en.svg)

There are two roles. **The team** writes code and pushes; it does not
need to know what Kubernetes is. **Whoever operates** installs aegis,
signs projects up and looks at the console now and then; it helps to
know what a cluster is, because when something stops, the diagnosis is
theirs. In a small team they are usually the same person.

## What it does not do

Said before you find out:

- **It is not for hosting third parties.** Whoever can push to a
  project is trusted by the whole platform. Projects are isolated from
  each other, but not from the platform. It is a decision: aegis is for
  a team hosting itself.
- **One machine.** No high availability and no multiple nodes. If the
  machine goes down, the platform goes down with it; the backups exist
  to come back.
- **One operating system on the host.** Ubuntu, and nothing else for
  now. Other distributions are refused before anything is touched.
- **No web panel for administration.** The console shows; changes are
  made with commands and commits. On purpose: nothing runs until you
  commit it.
- **It is not instant.** The install takes hours, not minutes, because
  it builds and signs its own images. After that, a push takes as long
  as building your application takes.
- **It demands reading.** There is a wizard to install and a console to
  look at, but operating a platform is operating a platform.

The complete, measured list is further down in «What is not there yet».

## What it looks like

![The console: Projects, with an instance's five projects and the worst state of each section beside its entry](docs/assets/console-projects.png)

The console opens in your browser over an SSH tunnel and shows your
projects, the deployments, the domains, the traffic, the storage, the
security and the machine. Everything has one of four states:

![Four states: fine, wrong, attention, could not look](docs/assets/states.en.svg)

The fourth state is the important one. When something could not be
measured, the console does not paint it green: it says so.

![Deployments: the last sixty pushes, each with its four links measured](docs/assets/console-deployments.png)

## Status

**Alpha.** It is the first version somebody else can install from this
repository. It works, it is tested and it is used daily on the author's
instance, but few people have installed it yet and your machine will
probably find something the author's did not. If it does, there is an
issue template that asks for exactly what is needed to diagnose it.

Where a complete install has run, from zero and with no intervention:

| system | result |
|---|---|
| Ubuntu 26.04, on lab VMs | several clean installs end to end, with the domain on Cloudflare, an application published and the recovery from backup tested |
| Ubuntu, on a rented VPS | the first complete install, with the profile without a domain |
| Arch Linux and Debian 13, in the lab | clean installs through the experimental lane; the installer does not accept them outside the lab yet |
| the author's machine, Ubuntu with a GPU | in daily use: pushes, off-site backups, updates and the vulnerability book every morning |

Every run that failed left a fix and a check that watches it. What the
product says about itself, as it came out on 2026-10-14 on the tree of
commit `39d2405` (no cluster):

```
$ aegis verify --profile both
══ STATIC VERIFICATION: ALL PASS (292 checks, 1 not evaluated) ══
   no check reads the profile yet (AEGIS_VERIFY_PROFILE): both profiles are one pass, run once as cloudflare — the second comes back the day a check reads it
```

Each of those 293 checks carries its *tooth*: a mutation that proves the
check turns red when it should. `aegis verify --teeth` walks the 1,688
mutations in minutes. The details of each run, with their numbers as
they came out, are in [docs/how-it-works.md](docs/how-it-works.md).

## Before you start

| | |
|---|---|
| **Host** | **Ubuntu 24.04 or newer**, with `sudo`. Other distributions (Arch, CachyOS, Fedora, Debian, Mint, Pop!_OS) are refused before anything is touched: aegis uses `apt` and Ubuntu's defaults. `amd64` only. |
| **Resources** | 4 CPU and 16 GB of RAM is what has been run. With 8 GB it starts without AI and without margin. 25 GB free on `/`. `aegis host measure` measures your machine; `aegis host budget` says whether what the platform reserves fits in what the machine leaves. |
| **If you share the machine** | With a graphical session, aegis reserves a memory floor for the desktop and never touches it. `aegis host floor --set` changes it. |
| **GPU (optional)** | For the AI's GPU lane: an NVIDIA card with driver 570 or newer. It is shared with your desktop; `aegis host show` says how much VRAM there is. |
| **Network** | Outbound internet over IPv4, a clock on time. The preflight probes and repairs what it can, and switches IPv6 off persistently. |
| **GitHub** | An account with `gh auth login` done and a git identity configured. The init creates two repositories (platform and canary) and then one per application. A dedicated account or organization is the most comfortable. |
| **Cloudflare (optional)** | A zone in your account and **Zero Trust switched on** (free, once, at one.dash.cloudflare.com), for the `cloudflare` profile: public hostnames, a tunnel, Let's Encrypt TLS and the consoles behind Access. Without it, the `local` profile raises the same platform on names that resolve to the host, with TLS from its own CA. |

What to have at hand:

- **A safe place for the age key.** It is the root of trust: it decrypts
  everything, and losing it is losing everything encrypted, backups
  included. Phase 10 generates it, shows it exactly once (in an in-memory
  file you read from another terminal, never on the init's screen) and
  demands a backup it validates for real. Decide beforehand where it
  goes (a password manager, a USB stick, paper) and that it is not the
  same host.
- **With Cloudflare:** the account ID, the zone ID and one master
  credential (the Global API Key, or a token with «Account API Tokens:
  Edit»). The init mints its two scoped tokens with it and does not keep
  it.
- **With no operator present** (`--non-interactive`):
  `AEGIS_AGE_BACKUP_FILE` and, with Cloudflare, `CF_MASTER_FILE`.

You do not need to prepare cosign keys, certificates, DNS records, the
tunnel or the internal registry's credentials. The init generates all of
them.

## Install

```bash
git clone https://github.com/MEMEMEMEMEMEMEDev/aegis-infra && cd aegis-infra
./bin/aegis preflight      # leaves the machine ready, or says what is missing
gh auth login              # your GitHub account: the init creates the repos for you
tmux new -s aegis          # the run is long; a dropped ssh must not kill it
./bin/aegis init           # the wizard asks what it cannot infer, then sixteen phases
```

It takes hours, not minutes. The long phase is 80, which mirrors and
builds the platform's images. From here on this page writes `aegis`
alone: it is `./bin/aegis` from the checkout, and `aegis --help` is the
map.

**What the wizard asks.** The edge profile (`cloudflare` or `local`),
the names of the two repositories, the root domain, whether you want the
AI subsystem (`no`, `cpu` or `gpu`: it decides how much memory is needed)
and, with `cloudflare`, the two IDs. It infers the rest: the GitHub owner
from the `gh` session, the email from `git config`. It prints a summary,
asks for confirmation and writes `~/aegis/aegis.conf`.

**Where everything lives.** This checkout is the product and is not
written to during a run. The instance lives in `~/aegis`: the
configuration in `aegis.conf`, the platform repository in `platform/`,
the phase markers and the gates in `.init-state/`, the encrypted store
in `.state-secrets/`.

**When it finishes.** The consoles hang off the root domain: `argocd.`,
`jenkins.`, `grafana.` and `ntfy.<domain>`. At `aegis.<domain>` lives the
canary, the first application the platform built, signed and deployed.
With `cloudflare` the consoles sit behind Cloudflare Access; with
`local`, the browser will warn until you import the CA. The admin
passwords are born encrypted in `~/aegis/.state-secrets/` and are read
with the age key:

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/aegis.key
sops -d --input-type binary --output-type binary ~/aegis/.state-secrets/jenkins_admin_pass.enc
```

The routine, afterwards:

```bash
aegis check               # measures the live cluster against what is declared; writes nothing
aegis init --list         # which phases exist and which passed
aegis vulns               # what is owed, since when, until when and who fixes it
```

<details>
<summary><b>If it stops</b></summary>

When a phase fails, the init stops there and leaves its gate recorded.
Fix the cause and resume:

```bash
aegis init --from 30      # resume from phase 30
aegis init --only 60      # repeat a single phase
aegis init --check        # measure without changing anything
aegis init-log            # the same as init, leaving a complete dossier of the run
```

`aegis init-log` prints the dossier's path before it starts. The black
box is `.init-state/gates.jsonl`; `docs/OPERATE.md` says where to start
diagnosing. If you are going to ask for help, the issue template «The
install stopped» asks for exactly three things: the `fail` line of that
file, the end of the dossier and, if the cluster answers, `aegis check
--json`.

To start from scratch on the same host:

```bash
aegis destroy             # without --yes it only says what it would remove
aegis destroy --yes --k3s # removes the edge, the bridge and the cluster
aegis init --reset-state  # forgets every gate and starts again
```

`aegis destroy` does not delete the GitHub repositories: they carry a
topic that marks them as the init's own, and a new run reuses them.

</details>

With your own domain in Cloudflare and your GPU, the whole journey is in
[docs/journeys/your-machine.md](docs/journeys/your-machine.md): what to
prepare, what to expect from each phase and what to send when something
stops.

## Your first application

Everything happens in the instance's platform repository. The contracts
live there, in `orgs/`, and that is where the commit is made.

```bash
cd ~/aegis/platform
aegis app new shop --template base   # writes contract, skeleton, derivations and secrets; touches nothing outside
git diff                             # read what it generated
git add -A && git commit -m "org: shop" && git push
aegis sync root                      # ArgoCD picks up the new organization
aegis app apply shop                 # creates the repo, the deploy key and the webhook on GitHub
```

From the first push to the application's repository, the platform builds
it, scans it, signs it, deploys it and exposes it. There are six templates
(`base`, `static`, `service-node`, `service-python`, `service-java`,
`worker-go`) and a template is used once: from there on the contract and
the repository are yours. To change something, edit the contract and
derive again:

```bash
$EDITOR orgs/shop.yaml               # add postgres, a bucket, another service, a secret
aegis org plan orgs/shop.yaml        # what would change, without writing
aegis org apply orgs/shop.yaml       # writes the manifests
aegis secret create orgs/shop.yaml   # if new secrets appeared
aegis app rebase shop                # brings an existing app onto the current pipeline
```

`seed/platform/docs/platform-for-developers.md` is the page for the
team that is going to push: what happens to each push and which rules
reject it.

## The console

```bash
aegis console serve            # http://127.0.0.1:7391
```

A visual layer on top of the commands. Every screen is drawn from the
documents the commands already emit; it measures nothing of its own and
there is nothing it can run that you cannot. It has no AI agent: a
platform whose job is to say what is true about your machine does not
guess.

It is organized like the consoles you already know: nine screens
(Projects, Deployments, Domains, Traffic, Storage, Plans, Security,
Machine and Health), and beside each entry the worst state of what feeds
it. It signs a project up in three cards and writes the contract, the
manifests and the secrets that are missing. It does not commit, push,
apply or touch the cluster: nothing runs until you commit.

It comes with a guided tour of sixteen steps. It is not published through
the tunnel: you get in with `ssh -L 7391:127.0.0.1:7391`. The why, the
security model and what is missing are in [docs/console.md](docs/console.md).

## The commands

`aegis --help` prints the menu and `aegis <cmd> --help` the detail of
each one. The contract is the same for all of them: `0` done or already
so, `1` wrong or missing, `2` could not evaluate, `3` invalid usage.

| group | commands |
|---|---|
| setup | `aegis preflight`, `aegis init`, `aegis init-log`, `aegis verify`, `aegis destroy` |
| apps | `aegis app`, `aegis org`, `aegis quota`, `aegis repos`, `aegis image`, `aegis secret` |
| operate | `aegis check`, `aegis console`, `aegis update`, `aegis tenant`, `aegis traffic`, `aegis capacity`, `aegis builds`, `aegis vulns`, `aegis host`, `aegis sync`, `aegis seed`, `aegis ai` |
| infra | `aegis ci`, `aegis edge`, `aegis registry`, `aegis rotate`, `aegis webhook` |
| backup | `aegis data`, `aegis state` |

<details>
<summary><b>Every command, in one line</b></summary>

**setup**

| command | what it does |
|---|---|
| `aegis preflight` | Leaves the machine in the state the init needs. With no arguments it acts and repairs. |
| `aegis init` | Brings up the platform phase by phase and records a gate per step. `--from N`, `--only N`, `--check`, `--list`, `--reset-state`, `--configure`, `--non-interactive`. |
| `aegis init-log` | `aegis init` under `script`, leaving a complete dossier of the run. |
| `aegis verify` | The static checks, no cluster. `--profile cloudflare\|local\|both`, `--only NNN`, `--teeth [NNN]`, `--harness`, `--list`. |
| `aegis destroy` | Undoes the init's footprint; `--k3s` the cluster too; `--purge-secrets`, the store. Without `--yes` it only says what it would do. |

**apps**

| command | what it does |
|---|---|
| `aegis app` | `new` writes the whole sign-up to files without touching anything outside; `apply` does the GitHub steps: repo, deploy key, webhook (`--check` to see it first); `rebase` brings an existing app onto the current pipeline. |
| `aegis org` | `plan` shows what would change; `apply` writes the manifests; `validate`, `list`, `schema`, `edge`, `routes`, `plan-delete`, `delete`, `migrate`. |
| `aegis quota` | The plans a project may take. `list`, `add`, `set`, `remove`. Never a number in a contract. |
| `aegis repos` | The account's repositories, with their language and which organization deploys them. |
| `aegis image` | The base images the platform builds and signs. `request`, `list`, `from`, `check`, `gc`. |
| `aegis secret` | `create` the encrypted secrets that are missing; `put` stores a secret the platform cannot invent; `rotate` the material; `move` to another namespace. |

**operate**

| command | what it does |
|---|---|
| `aegis check` | The round: measures the live cluster against what is declared. Writes nothing. |
| `aegis console` | `serve` the console on loopback; `capture` saves a state of the world as a case; `list` the cases; `draw` draws a case's screens with no server. |
| `aegis update` | `inventory` what runs and what exists upstream; `plan` what a window would raise; `window` the whole protocol, dry unless `--yes`; `rollback`, `status`, `metrics`. See [the protocol](seed/platform/docs/protocols/updates.md). |
| `aegis tenant` | One organization as the cluster has it, against what its contract declares. |
| `aegis traffic` | What arrived at each organization, read from Traefik's metrics, reconciled against the total. |
| `aegis capacity` | Does another organization fit? The node against what the plans cost. |
| `aegis builds` | What happened to each push: built, scanned, signed, digest written. |
| `aegis vulns` | The known vulnerabilities of what runs: what is owed, since when, until when and who fixes it. It reads the books image-watch keeps every morning. |
| `aegis host` | `measure` the machine; `show`; `floor` the desktop's memory floor; `budget` whether the platform fits; `reservation` what the node sets aside; `requires` the minimums; `metrics`. |
| `aegis sync` | An ArgoCD sync of the named apps; `--drifted` everything that is not Synced. |
| `aegis seed` | `diff` what the seed changed and this instance lacks; `apply` brings it over keeping pins and derived blocks, in a commit you read and push. |
| `aegis ai` | The operator's control over the AI subsystem: `status`, `start`, `stop`, `open`, `demo`, `max`, `logs`, `engine-logs`, `images`, `bases`, `models`, `seed`, `key`. |

**infra**

| command | what it does |
|---|---|
| `aegis ci` | `build` fires the platform's image jobs in order; `jobs`; `digests`; `quiet on\|off` so that a push does not build on a half-changed platform. |
| `aegis edge` | `check` compares the live hostnames with the ones derived from the contracts. |
| `aegis registry` | `check` the internal registry credential at its ten destinations; `rotate` generates it anew. |
| `aegis rotate` | The rotation protocol: `list`, `check`, `run`, `continue`. It rotates every credential the init generates except the two roots (the age key and the cosign key), which have protocols of their own. |
| `aegis webhook` | `check` that every repository with a job has a webhook; `apply` creates the missing ones. |

**backup**

| command | what it does |
|---|---|
| `aegis data` | The tenants' data, one bundle per organization: `backup`, `list`, `restore`, `size`, `remote` (the off-site destination: `bucket`, `adopt`, `push`, `status`, `cadence`). |
| `aegis state` | `backup` and `restore` of the three states that live only on this machine: the encrypted store, the phase markers and the edge's tfstate. |

`state` is the machine; `data` is the tenants. A backup of one does not
restore the other.

</details>

## How it works, in short

For whoever wants to open the hood. The long version, with every
mechanism and every number recomputed, is
[docs/how-it-works.md](docs/how-it-works.md).

<details>
<summary><b>Sixteen phases, four stages</b></summary>

```mermaid
flowchart LR
    subgraph A["1. the host and the trust"]
        direction TB
        a0["00 preflight"] --> a1["05 host"] --> a2["10 age-ceremony<br/>the root of trust"] --> a3["12 workrepos<br/>the repos the init manages"] --> a4["15 third-parties"]
    end
    subgraph B["2. the cluster and the edge"]
        direction TB
        b0["20 k3s"] --> b1["25 edge-tofu<br/>cloudflare or local"] --> b2["30 argocd"] --> b3["35 gitops<br/>control passes to git"]
    end
    subgraph C["3. registry and CI"]
        direction TB
        c0["40 registry-pki"] --> c1["50 jenkins"] --> c2["60 webhook"] --> c3["70 deploy-auto<br/>the canary"]
    end
    subgraph D["4. chain, watch and AI"]
        direction TB
        d0["80 supply-chain<br/>Kyverno in Enforce"] --> d1["85 observability"] --> d2["87 ai<br/>if asked for"]
    end
    A --> B --> C --> D
```

Each phase leaves a marker and records its gates in
`.init-state/gates.jsonl`. The order matters: the admission policy is
switched on when a signed image already exists to admit, and
observability goes last because it measures what already exists. The
table of the sixteen phases, one by one, is in `docs/how-it-works.md`.

</details>

<details>
<summary><b>One contract, and everything else derived</b></summary>

```mermaid
flowchart LR
    c["orgs/shop.yaml<br/>the contract: services, public routes,<br/>database, bucket, plan"]
    c --> n["namespace + quotas<br/>+ PSS restricted"]
    c --> np["NetworkPolicies<br/>default-deny"]
    c --> r["RBAC"]
    c --> j["Jenkins jobs"]
    c --> a["ArgoCD apps"]
    c --> h["hostnames and routes"]
    c --> s["encrypted secrets"]
    c --> b["backups per organization"]
```

One YAML per organization. `aegis org apply` regenerates everything from
the contract, in marked blocks rewritten whole; `aegis org plan` shows
what would change before touching anything. The contract's keys are
Spanish on purpose (`organizacion`, `dominio`, `cuota`, `servicios`):
they are the one vocabulary the product team writes.

</details>

<details>
<summary><b>The supply chain, in six steps</b></summary>

1. A push reaches Jenkins through a webhook (or by polling, with `local`).
2. kaniko builds the image in an unprivileged pod, on a base the
   platform mirrored and signed.
3. Trivy scans, layer by layer. What your change brings with a fixable
   critical or high vulnerability stops the build; what the base brings
   is the platform's and has its own clock; what was already running is
   written down as debt with a date (15 days for a critical, 30 for a
   high), and an exploited vulnerability has no deadline.
4. cosign signs by digest, never by tag, with the instance's key.
5. The pipeline writes the digest into the kustomize overlay and
   commits. ArgoCD deploys.
6. Kyverno, in Enforce, refuses at admission any image without a valid
   signature.

The platform's own images follow the same discipline: one job mirrors
only pinned versions from outside, another builds the owned bases and
tests them by running them before signing them, and `image-watch`
re-scans everything every morning and keeps the books `aegis vulns`
reads.

</details>

<details>
<summary><b>Product and instance, and six rules</b></summary>

This repository is the product: `bin/`, `libexec/` and `lib/` are the
commands; `init/` the phases; `verify/` the checks and their teeth;
`seed/` what ships. It is read-only during a run. The instance is
`~/aegis`: its configuration, its GitOps repository on GitHub, its
markers and its encrypted store. When the product changes, `git pull`
brings the fix to the machine and `aegis seed apply` brings it to the
instance, keeping what is its own.

- The contract is the single source of truth. Everything else is
  derived.
- A command run again with the work done ends in «nothing to do».
- Four outcomes, always: `0` done or already so, `1` wrong or missing,
  `2` could not evaluate, `3` invalid usage. An instrument that never
  reached its subject does not say the subject is fine.
- A gate with no subject is recorded as such. A build that never
  appeared is a failure.
- Every check comes with the mutation that proves it bites
  (`aegis verify --teeth`).
- The product carries nobody's addresses, accounts or paths. Two checks
  watch over it.

</details>

## What is not there yet

Said plainly, because the checks would say it anyway.

- **The trust model is a team's, by decision.** Isolation holds between
  organizations; it does not hold between an application repository and
  the platform: whoever can push to an application repository is trusted
  by the whole platform. aegis is for a small team hosting itself, not
  for hosting third parties. A version with that boundary closed exists
  as a working branch and asks for runs of its own; it is not what comes
  next.
- As far as the author knows, nobody else has installed the `cloudflare`
  profile from zero yet: it has run on the author's lab machines, and a
  second person is trying it now.
- One repository per service. The monorepo is not first class.
- Restoring between instances is not automatic: the bundle comes
  encrypted with the age key of the instance that made it, and `restore`
  demands `--force` when it detects that the database credential changed.
- Kyverno reaches only registries signed by the instance's CA; a public
  image is refused with an `x509` error, not with «no signature».
- A single node. No HA and no multi-cluster: it is a platform for one
  team and its projects, not for a fleet. A 4-CPU node admits one build
  at a time. Without the AI subsystem, the seed asks for about 5.5 GiB
  of memory and may grow to 14 at its ceilings; with the GPU lane, 16.5
  and 34. `aegis host budget` measures it on your machine.
- `amd64` only, and Ubuntu only on the host.
- The contract's keys are Spanish on purpose; elsewhere in the product
  Spanish identifiers remain to be retired, and the glossary lists them.
- The VRAM watcher only warns. When the desktop and the engines run out
  of card, aegis says so and takes nothing down.
- The console is the operator's. It runs on loopback and is reached
  over an SSH tunnel. The tenant's console does not exist.
- The console adds and changes, and never removes. Deleting a service is
  `aegis org` by hand.
- Outside the console, it still demands reading.

Next, in this order and with no dates: the `cloudflare` profile
installed by a second person; the tenant's console; the monorepo as a
first-class case.

## What is inside

```
bin/          the dispatcher (aegis <command>)
libexec/      one file per command
lib/          the shared helpers, bash and python
init/         the orchestrator and its sixteen phases
verify/       the checks, their teeth, the harnesses
seed/         what ships: the platform repo, the canary, the templates
console/      the measured cases the console is drawn and tested with
share/        the exit codes, the systemd units, the console's CSS
docs/         how it works, how it is operated, how it is changed; the glossary; the journeys
.github/      the verification on every push, and the issue and PR templates
```

In the cluster: k3s without the stock Traefik and servicelb, installed by
Ansible; ArgoCD with KSOPS; Jenkins with jobs as code and kaniko; Trivy,
cosign and Kyverno; Traefik and cert-manager with an internal CA;
cloudflared only with `cloudflare`; an internal image registry with its
own TLS; Garage (S3) and Postgres, MongoDB and Redis as service types,
with a bucket and a database per organization; VictoriaMetrics,
VictoriaLogs, Grafana, Vector, blackbox-exporter, Alertmanager and ntfy;
default-deny NetworkPolicies and PSS restricted in every tenant
namespace. Every version is pinned where it is used and `aegis update
inventory` reads them all.

Where to keep reading:

- [docs/how-it-works.md](docs/how-it-works.md), the long version of
  this page: phases, GitOps, the chain, tenants, secrets, backups, the
  verifier.
- [docs/journeys/your-machine.md](docs/journeys/your-machine.md), if you
  are going to install it with your domain and your GPU.
- [docs/OPERATE.md](docs/OPERATE.md), if you are going to operate an
  instance: expected state, diagnosis, recovery tools.
- [docs/console.md](docs/console.md), if you are going to use the
  console.
- [docs/AGENTS.md](docs/AGENTS.md), if you are going to change the
  product: the method and the rules born from real incidents.
- `docs/glossary.md` is the vocabulary, and `aegis verify` enforces it.
- `seed/platform/docs/failure-modes.md` catalogues the failure classes
  with their signature and their fix.
- `seed/platform/docs/platform-for-developers.md` is what the team that
  pushes reads.

## About the language and the history

The product is in English: code, messages, the seed and the
documentation. The Spanish README is the front page; this is the English
version. The commit history is a working record: in Spanish until
September 2026 and in English since, and it tells how each bug was
found.

This history begins with the v3 rebuild. The earlier work (version 2)
lives in private repositories, because it carries the identity of one
particular instance: the author's, which was born on v2 and carried to
v3. This project did not come out of one session or one
prompt: every piece above has runs that failed behind it, and checks
that were born from them.

## Contributing, security, licence

- `CONTRIBUTING.md`: one item, one commit; one check per fix; one tooth
  per check; `aegis verify --profile both` green before committing.
  Nothing is done until a run validates it on a real instance.
- `SECURITY.md`: how to report a vulnerability privately, through this
  repository's private GitHub reporting, never in a public issue.
- Apache License, version 2.0; see `LICENSE`.
