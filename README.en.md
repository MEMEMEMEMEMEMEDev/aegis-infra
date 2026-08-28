# aegis

**A self-hosted GitOps platform that installs itself, and then proves it.**

Léelo en español: [README.md](README.md)

![What happens to a git push: build, scan, sign, deploy, expose; unsigned, refused](docs/assets/pipeline.svg)

You bring a Linux box and a GitHub account. `aegis init` turns them
into a Kubernetes platform where every `git push` gets built in an
unprivileged pod, scanned, signed by digest, deployed by GitOps and
exposed to the internet with TLS — and where an unsigned image is
refused at admission, not noticed later.

> **Status: technical preview.** This is the version for developers
> and platform people. It is measured, not polished: the whole
> install has run end to end on a machine that was not the author's
> (see [where it has been run](#where-it-has-been-run)), and every
> claim below comes from a gate or a check that can be re-run. A
> friendlier layer — for people who do not want to read a
> Jenkinsfile, and for developers early in their career — is the
> next thing being built on top of this one. It is not here yet.

---

## What you get

- **A platform from one command.** `aegis init` runs fifteen
  idempotent phases: host, root of trust (age/sops), the GitOps repo
  it owns, k3s, the edge, ArgoCD, the internal registry and PKI,
  Jenkins, webhooks, a canary deploy, the supply chain and
  observability. Re-running converges: what is already done is
  skipped, what is missing is done.
- **A supply chain with teeth.** Build with kaniko, scan with Trivy
  (a fixable HIGH/CRITICAL is a red build), sign with cosign by digest,
  admit with Kyverno. The platform's own images come from a pinned
  mirror, its base images are built in-house and re-scanned daily
  against today's vulnerability database.
- **Tenants from a contract.** One YAML per organization
  (`orgs/<name>.yaml`) is the only truth: namespaces, quotas, network
  policies, RBAC, Jenkins jobs, ArgoCD apps, hostnames, secrets and
  backups are all *derived* from it. `aegis org apply` re-derives;
  nothing is written twice by hand.
- **Observability that watches itself.** VictoriaMetrics, vmalert,
  Grafana, blackbox probes and an events log, with alerts to your
  phone through ntfy — and a rule that every metric an alert reads is
  produced by something, so a broken exporter cannot go quiet.
- **Recovery, exercised.** `aegis state backup` (the machine's
  state), `aegis data backup` (the tenants' data), `aegis rotate`
  (every credential the init generates can be rotated), `aegis
  destroy` (undo it all), and a rehearsal document for doing this on a
  machine that is not yours.
- **A verifier.** `aegis verify` runs 136 static checks on the
  artifact without a cluster. Each check has a *tooth*: a mutation
  that breaks what the check protects, so that the check is proven to
  bite. `aegis check` is the same idea against a live cluster.

## Where it has been run

Measured, not remembered. The dates are the days the runs happened.

| where | what | result |
|---|---|---|
| A rented VPS — 4 CPU / 16 GB, Ubuntu, nothing on it but ssh; a **fresh GitHub account**; **no domain** (`EDGE=local`) | `aegis init` from zero (2026-08-27) | 15/15 phases, 174 gates passed, 20 recorded as *not evaluable* (they need a public edge) |
| same host | two tenants signed up from their contracts, their data restored from backups, catalogue served over HTTPS | done; 12 products and 4 orders, photos and users where the backup said they would be |
| same host | `aegis state backup` → `aegis state restore` into a second instance directory | round-trip verified |
| same host, **dirty** | `aegis destroy --k3s` and a second `aegis init` over the leftovers (2026-08-27) | 15/15 phases; the three things a previous instance leaves behind (an inherited admission policy, a stale CA, a registry that no longer exists) are now detected and repaired by the init itself |
| the author's own machine | the lineage this rebuild comes from has been serving the author's public sites behind a Cloudflare edge for about a year | in daily use |

That first foreign run found about thirty defects that the static
checks could not see — not bugs in the code, bugs in the *distance*
between the product and its first real instance. They are all
closed, each with a check, and the classes are named in
`seed/platform/docs/failure-modes.md`. The rehearsal itself is written
down so that it can be repeated: `docs/journeys/foreign-instance.md`.

**What has not been measured yet:** the `cloudflare` edge profile of
*this* rebuild on a foreign machine (the lineage runs it at home; the
profile's gates are recorded as not evaluable under `EDGE=local`).

## Before you start: what to have ready

To run it **in full** you need GitHub **and** Cloudflare. Without
Cloudflare, `EDGE=local` gives you the whole platform — build, scan,
signature, admission, GitOps, observability — on names that resolve
to the host, and the public-edge gates (about twenty) are recorded as
*not evaluable*. It is a good first run; it is not the full one.

- **GitHub.** An account with `gh auth login` done; the preflight
  says which scopes it asks for (`repo`, `delete_repo`). The init
  **creates and owns** two repos with new names, and later one per
  application; deploy keys and webhooks are its job, not yours. A
  dedicated account or organization is the most comfortable.
- **Cloudflare, for the `cloudflare` profile.** A zone in your
  account (a domain whose nameservers point at Cloudflare), the
  account ID and the zone ID (the wizard asks for them), and **one
  ephemeral master credential** with which the init mints its two
  scoped tokens: your *Global API Key* or an account token with the
  permission "Account API Tokens: Edit". It lives only in memory
  during phase `15`; if you pass it through a file (`CF_MASTER_FILE`),
  destroy the file afterwards — the init reminds you. Knowing how to
  create tokens in the Cloudflare dashboard before you sit down helps.
- **A safe place for the age key, decided beforehand.** It is the
  root of trust: it decrypts everything, and losing it is losing
  everything encrypted, state backups included (they are encrypted
  with it). Phase `10` generates it, lets you read it **once and
  outside the pane** (on tmpfs, from another terminal), and demands a
  backup validated by a real encrypt/decrypt round trip; it suggests
  an offline USB stick plus a folder off the machine. Have the place
  ready (password manager, USB, paper) and not on the same host. And
  **never record the session** (`script`, `tmux pipe-pane`,
  asciinema) during that phase.
- **Unattended** (`--non-interactive`): `AEGIS_AGE_BACKUP_FILE`
  (ideally under `/dev/shm`) for the key's backup and
  `CF_MASTER_FILE` for the Cloudflare credential; the init refuses to
  run without them.
- **A contact email** for certificates (the wizard infers it from
  `git config`) and an ssh session that will not drop: tmux.

What you do **not** need to prepare: cosign keys, certificates, DNS
records, the tunnel, the internal registry's credentials. The init
generates all of it, and `aegis rotate` can rotate it.

## Requirements

- A Linux host you have `sudo` on. Ubuntu is what has been run; the
  preflight installs what it needs with `apt`.
- 4 CPU and 8 GB of RAM are enough (the preflight warns below 7 GB;
  Jenkins, Kyverno and Trivy get tight). 25 GB free on `/`.
- Outbound internet: GitHub, the container registries the mirror
  pulls from, k3s.
- A GitHub account. The init **creates and owns** the two repos it
  needs (the platform repo and a canary) through `gh`; it needs an
  authenticated `gh` session, and the preflight says which scopes it
  asks for.
- Optional: a Cloudflare account with a zone, for `EDGE=cloudflare`
  (public hostnames, a tunnel, TLS from an ACME issuer). Without it,
  `EDGE=local` gives you the same platform on names that resolve to
  the host, with TLS from the instance's own CA.

## Quick start

```bash
git clone <this repository> ~/aegis-v3
cd ~/aegis-v3
./bin/aegis preflight      # leaves the machine as the init needs it, or says why not
./bin/aegis init           # a guided configuration, then fifteen phases
aegis check                # the routine round against the live cluster
```

`aegis init` asks a handful of questions (the edge profile, the
GitHub owner, the names of the two repos, a contact email for
certificates) and writes `~/aegis/aegis.conf`. Everything else is
derived. The run is resumable: `aegis init --from <phase>` after a
failure, `aegis init --check` to measure without changing anything,
`aegis init-log` to leave a dossier of the whole run.

Signing an application up, from a template:

```bash
aegis app new shop --template base   # writes the contract and the skeletons; touches nothing
git diff                             # read what it derived
aegis app apply                      # creates the repos, deploy keys and webhooks
```

From that push on, the application is built, scanned, signed,
deployed and exposed by the platform. `seed/platform/docs/platform-for-developers.md`
is the page to hand to the team that will push to it.

## How it is built (the ideas that order everything else)

- **Product and instance are two things.** The product is this
  repository, read-only during a run. The instance is one machine's
  living state — the GitOps repo, the phase markers, the encrypted
  store, the configuration. One file decides where each lives, in
  bash and in python, so two commands cannot disagree.
- **The contract is the only truth.** Templates generate contracts;
  everything else is derived from them, and the derivation is
  idempotent (a marked block, re-written whole, every time).
- **Converge, do not execute.** Every command re-run with the work
  already done ends in *nothing to do*.
- **Four outcomes, always.** `0` done or already so · `1` wrong or
  missing · `2` could not evaluate · `3` invalid usage. *Could not
  evaluate* is a first-class answer: an instrument that never reached
  its subject does not say the subject is fine.
- **Silence is never success.** A gate with no subject is recorded as
  such; a build that never appeared is a failure; a wizard that could
  not write the file dies instead of continuing.
- **A check that does not bite does not exist.** Every check ships
  with the mutation that proves it fails when it should.
- **The product names no machine and no person.** The seed carries
  placeholders, never values; two checks keep addresses and identities
  out, so that what installs here installs anywhere.

## The map

```
bin/          the dispatcher (aegis <command>)
libexec/      one file per command
lib/          the shared helpers, bash and python
init/         the orchestrator and its fifteen phases
verify/       the checks, their teeth, the harnesses
seed/         what ships: the platform repo, the canary, the templates
docs/         AGENTS.md (how to change this), OPERATE.md (how to run it),
              the glossary, the design journeys
```

Start with `docs/AGENTS.md` if you are going to change it, and
`docs/OPERATE.md` if you are going to run it. `docs/glossary.md` is
the vocabulary, and `aegis verify` enforces it.

## What is not there yet

Said plainly, because the checks would say it anyway.

- The `cloudflare` profile of this rebuild has not been run on a
  foreign machine.
- A fix to the seed does not reach an instance that was already
  seeded; re-seeding a living instance is manual.
- `aegis data restore` restores the database, not the objects in the
  bucket (it says so when it runs).
- One application template (`base`). A static-site template and a
  multi-service Jenkinsfile are designed, not shipped.
- Single node. No HA, no multi-cluster. It is a platform for a team
  and its projects, not for a fleet.
- Some identifiers inside the seed are still in Spanish, on purpose:
  each one moves with the instance that reads it, and the glossary
  lists every one that is pending.
- It expects you to read. The friendlier layer is the next piece of
  work, and it is being built on top of this one rather than instead
  of it.

## About this history

This history starts with the v3 rebuild and tells only that part. The
bulk of the work — version 2, which still runs the author's own
instance, its platform repositories and the sessions before them —
lives in private repositories and is not here, because it carries the
identity of one concrete instance. It may be released some day. What
is worth knowing: this project did not come out of a single session or
a single prompt; every piece above has failed runs behind it, and
checks that were born from them.

## Contributing, security, licence

- `CONTRIBUTING.md` — the method is short and non-negotiable: one
  item, one commit; a check for every fix; a tooth for every check;
  `aegis verify` green before committing.
- `SECURITY.md` — how to report a vulnerability privately.
- Licensed under the Apache License, Version 2.0 — see `LICENSE`.
