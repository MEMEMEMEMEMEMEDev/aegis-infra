# CLI DESIGN — the dispatcher and the surface, in English

**Agreed on 2026-08-21.** This document says **what it should be**;
`cli/inconsistencies.md` says **what is wrong today**. The two are read
together.

## When

**Not now.** It is executed during the rebuild: a new seed, the current
instance deleted, aegis raised from zero. The reason is economics, not
taste: refactoring live means 77 dependencies moved with tweezers while
the instance keeps running; writing it right from the start is just
writing it right from the start.

Practical consequence: **`cli/inconsistencies.md` changes genre.** It stops
being a list of surgeries and becomes the specification the new code has
to meet. The seven cases of Disease E are not tasks: they are design
rules.

## Scope

What gets translated is **the surface**: command names, subcommands,
flags, and every piece of text a `--help` prints.

What stays as it is: the contracts' vocabulary, the code's comments, the
messages a command narrates while it runs, and the derived names in the
cluster.

**The cut goes at the `--help`.** You cannot have a `new` subcommand
explained in Spanish. But `listo — quedó escrito, nada tocó el mundo`
stays in Spanish, and that is fine: the comments are the repo's best
asset and translating them is a lot of effort, a risk of flattening the
prose, and almost no effect on somebody who has not stayed yet.

Mixing languages **inside** one layer is ugly. **Between** layers it is
normal. Finish one layer before starting the next.

---

## 1 · The dispatcher

`aegis <command> <subcommand> [options]`, with git's mechanism: **`aegis
foo` looks for an executable called `aegis-foo` and runs it.**

```
aegis app new shop
  └─► the dispatcher sees "app", looks for aegis-app in its libexec
      └─► exec aegis-app new shop          (the command never notices)
```

Why this and not a monolith with one giant `case`:

- **Adding a command is dropping in a file.** There is no registry to
  update, no list of imports to forget.
- Each command remains executable on its own — the scripts that already
  invoke them directly do not need to go through the dispatcher.
- **The files are already called `aegis-*`**: the convention has been
  implemented by accident since day one.

### The name lives in exactly one place

The dispatcher takes its own name from `argv[0]`. If one day the product
is not called aegis, **renaming the binary renames the entire CLI** and
there are no twenty files to touch. That is the technical reason this
layer is worth it even if the name never changes.

### Installation

A phase of the init leaves the dispatcher in the PATH (today the init
installs `kubectl` and `cosign` into `/usr/local/bin` but **does not
install its own commands** — you have to know which folder to go to and
run `bin/aegis-app`). With a single entrypoint and declared subcommands,
shell completion comes almost for free.

---

## 2 · The help is DERIVED

It is the house doctrine applied to the CLI: **nobody maintains the
menu.**

Each command declares two lines of metadata in its header:

```bash
# aegis-summary: Provision an organization from its contract
# aegis-group:   apps
```

`aegis` with no arguments reads those lines from the ~20 files and
assembles the grouped menu. A new command appears in the help **by
existing**, the same way an organization appears in the cluster by having
a contract.

### The tooth

`aegis verify` demands that every `aegis-*` declare `summary` and
`group`, exist, and be executable. **Documentation that goes stale stops
being an oversight and becomes a red test.**

This is not decoration: today **out of the 12 commands in
`platform/bin/` exactly one has any check that verifies its existence**,
and that check is case A2 of the register. Without this tooth, the
dispatcher adds one more layer where something can go missing in
silence.

### The anatomy of a `--help` that is worth having

1. **Usage** with the standard grammar: `aegis app new <ORG>
   [--template NAME]` — angle brackets mandatory, square brackets
   optional.
2. **One line** of what it does.
3. **Subcommands and options**, aligned.
4. **Examples.** The most skipped and the most used.
5. **Exit codes.** Here aegis has a need no other CLI has: the three
   outcomes (`done` / `already` / `NOT-EVALUABLE`) map to `0 / 0 / 1`,
   and the fact that "I could not evaluate" returns an error **has to be
   written down** because nobody guesses it.
6. **Where the protocol lives** that this command implements.

The python commands get 1–3 for free from argparse. The bash ones write
it by hand, and that is exactly why they derive it: they need a shared
helper in `lib/common.sh`.

---

## 3 · The grammar

### Rule 1 — verbs are subcommands, not flags

The tell-tale symptom: **a mandatory, mutually exclusive flag**
(`add_mutually_exclusive_group(required=True)`) is not an option, it is a
verb in disguise.

```
aegis-registro --revisar|--rotar        →  aegis registry check|rotate
aegis-respaldo --capturar|--listar|...  →  aegis data backup|list|restore
aegis-secreto  --todos|--rotar|...      →  aegis secret create|rotate|move
aegis-webhook  --aplicar                →  aegis webhook check|apply
```

This is not a redesign: it is doing the same rename properly. Writing
`--rotate` instead of `--rotar` costs exactly the same as writing
`rotate`, but it bakes the defect in forever.

### Rule 2 — the "look without touching" mode is spelled ONE way

The concept already exists and it is fine; the spelling is not. Today it
is written `--check`, `plan`, `--revisar`, `--listar`, `--verificar`,
`plan-borrar` — six spellings for the same idea, and `aegis-rotate.sh`
uses `--revisar` **and** `--verificar` in the same script for two things
that in English would both be *check*.

One single form across the whole house.

### Rule 3 — one concept, one language, one name

The register documents ten same-concept-two-language collisions
(`edge`/`borde`, `backup`/`respaldo`, `rotate`/`rotar`,
`canary`/`canario`, `template`/`plantilla`, `tenant`/`organización`…).
The new tree does not inherit them.

---

## 4 · The command map

| Group | Today | New |
|---|---|---|
| **setup** | `aegis-preflight.sh` | `aegis preflight` |
| | `aegis-init.sh` | `aegis init` |
| | `verify-static.sh` | `aegis verify` |
| | `aegis-destroy.sh` | `aegis destroy` |
| **apps** | `aegis-app nueva\|aplicar` | `aegis app new\|apply` |
| | `aegis-org plan\|aplicar\|validar\|borde\|ruteo\|plan-borrar\|borrar\|migrar` | `aegis org plan\|apply\|validate\|edge\|routes\|plan-delete\|delete\|migrate` |
| | `aegis-secreto --todos\|--rotar\|--reubicar` | `aegis secret create\|rotate\|move` |
| **operate** | `aegis-chequeo` | `aegis check` |
| | `aegis-sync --fuera-de-linea` | `aegis sync --drifted` |
| | `ai status\|init\|abrir\|cerrar\|max\|demo\|log` | `aegis ai status\|start\|stop\|max\|demo\|logs` |
| **infra** | `aegis-borde` | `aegis edge check` |
| | `aegis-webhook --aplicar` | `aegis webhook check\|apply` |
| | `aegis-registro --revisar\|--rotar` | `aegis registry check\|rotate` |
| | `aegis-rotate.sh` | `aegis rotate` |
| **backup** | `aegis-backup.sh` / `aegis-restore.sh` | `aegis state backup\|restore` |
| | `aegis-respaldo --capturar\|--listar\|--restaurar` | `aegis data backup\|list\|restore` |
| **dev** | `aegis-semilla` | `aegis dev seed` |
| | `aegis-org-prueba`, `aegis-tipos-prueba` | `aegis dev test-org`, `aegis dev test-types` |

### Two collisions the rename uncovered

**`backup` was colliding with itself.** `aegis-backup.sh` saves the three
states that only live on the VM; `aegis-respaldo` saves the tenants'
data. In Spanish the collision was invisible because one said "backup"
and the other "respaldo"; in English both are *backup*. Hence `state` and
`data`.

**`ai init` was colliding with `aegis init`.** One turns the GPU on for N
hours, the other installs the entire platform. As subcommands of the same
binary that is a trap waiting for somebody tired. Hence `ai start`.

### What does NOT belong in the operator's CLI

`aegis-semilla` and the two acceptance tests are tools for **whoever
maintains aegis**, not for whoever operates it. They go under `aegis dev
...` or straight out of the dispatcher. kubectl does not ship its test
suite.

---

## 5 · Design rules that come from the register

These are not preferences: they are the seven cases of Disease E turned
into conditions the new code has to meet.

1. **No invoker without a guard.** Every place that executes another
   command first verifies that it exists, or handles the 127 explicitly.
   The "not-evaluable" branch cannot share code with "does not exist".
2. **No state communicated through prose.** A command that needs to know
   what another one did reads it from an rc or from a stable
   machine-readable line (`STATE=created`), **never by grepping a
   translatable message**. Today `aegis-app:713` greps `"webhook creado"`
   and that coupling is the only bomb that goes off when you touch the
   message layer.
3. **No absence is interpreted as a legitimate case without being
   distinguished from an error.** If check 4 does not find the generator,
   it has to ask itself whether there are contracts: with no contracts it
   is normal, with contracts it is a failure.
4. **`return 0` NEVER means "I could not do it".** `aegis-rotate.sh:757`
   returns success when the synchroniser is missing.
5. **A failure message does not attribute a cause it did not verify.**
   `aegis-rotate.sh:243/641` sends you off to write a verifier that
   already exists.
6. **Every parsed sentinel and the text that produces it live in the same
   file**, or there is a check that demands they match.
7. **Every declared command exists, is executable and announces itself.**
   The tooth from section 2.

---

## 6 · Inherited debt the new tree must not inherit

From the register, section H — things that are **already broken today**:

- `aegis-rotate.sh` announces itself as `aegis-rotar`, a name that does
  not exist.
- The `.tf` files cite `aegis-rotate --verificar`, without the `.sh`.
- `docs/protocols/organization.md` documents `aegis org rotar <org>
  <secreto>`, a phantom subcommand.
- **35 generated files carry `aegis org` (the dispatcher form, which does
  not exist yet) and `bin/aegis-org` in the same banner**, with a third
  banner format coexisting alongside. The generator must emit **one**
  convention so that re-derivation normalises all 38 in a single pass.
- The two acceptance tests are orphans: nobody runs them, `verify-static`
  does not invoke them, there is no CI.

---

## 7 · Open

- **Does the contract's vocabulary go to English?** Decided no for now
  (`organizacion:`, `usa:`, `cuota:` stay). If one day it does, it is a
  versioned migration with `aegis org migrate` and `version: 2`, never a
  find-and-replace: it renames live Kubernetes objects.
- **Does `aegis dev` go into the dispatcher or stay outside?**
- **Does `initiatedBy.username: "aegis-sync"`** get renamed? It stays
  engraved in ArgoCD's operation history; it is a datum, not a command.

---

## 8 · The first boot: the local profile, and the domain afterwards

**Decided on 2026-08-22.** Aegis installs **with no domain**. The wizard
asks «do you have a domain on Cloudflare?» and branches; whoever does not
have one gets a platform anyway. It is the friend test taken seriously:
the friend almost never has a domain.

### It is not a mode: it is another value

`ROOT_DOMAIN` is already a variable across the whole tree — derivations,
routes, contracts and probes do not know what value it carries. The local
profile puts `127-0-0-1.sslip.io` in it (or
`<lan-ip-with-hyphens>.sslip.io` to get in from the phone) and 90% of the
system never notices. sslip.io is a public DNS whose answer comes written
in the question: `blog.127-0-0-1.sslip.io → 127.0.0.1`. No account, no
registration, nothing that expires — the name IS the address.

The real differences are FOUR, and only four:

| piece | with a domain | local |
|---|---|---|
| phase 25 (tunnel + DNS + Access) | runs | skipped |
| certificates | Let's Encrypt | internal CA (already exists: the registry lives off it) |
| CI push→build | GitHub webhook | periodic polling of the multibranch (one line in the jobs derivation — today the derived jobs do NOT carry a periodic trigger and depend 100% on the webhook) |
| site probes | the full path through Cloudflare | straight against traefik, SAYING that they measure less |

Why an internal CA and not Let's Encrypt: LE rate-limits issuance PER
REGISTERED DOMAIN; with sslip.io the limit is shared with all of its
users worldwide. It is not a declined option — it does not exist.

### The domain adoption protocol (`aegis domain set`)

Adding the domain afterwards is NOT reinstalling, because everything that
carries the domain inside it is either DERIVED (aegis-org), or RENDERED
(phase 10), or in the CONTRACTS. The protocol: (1) a zone on Cloudflare +
tokens; (2) a new ROOT_DOMAIN + `dominio:` in the contracts; (3)
re-render + re-derivation (existing mechanisms); (4) phases 25 and 60,
idempotent; (5) issuer swap CA→ACME.

The ONLY new piece is the command that orchestrates and verifies those
steps: `aegis domain set <domain>`. It is worth having beyond the local
profile — it is also the path for MIGRATING domain, which today does not
exist.

### Wrinkles on the record (so as not to rediscover them)

- **The IP travels in the name**: DHCP changes the IP → the LAN names
  change. Default `127-0-0-1` (never changes); the LAN form is opt-in.
- **sslip.io is a third party**: its DNS down = local names that do not
  resolve with everything of yours alive. Emergency exit: a derived
  `/etc/hosts` (a pattern the init already uses for the registry).
- **The CA in the browser**: curl and containerd take it from the
  system's trust store; Firefox/Chrome use their own. Either a guided
  step in the wizard, or a clear warning.
- **ntfy from the phone**: requires the LAN form + the CA installed on
  the phone (or plain http on the LAN). To be resolved in
  implementation, not improvised.
