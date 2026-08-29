# Protocol: organizations and services

Status: **contract v1**. This document defines the surface an operator
—human or agent— touches in order to create organizations and services
in aegis. It is written so as never to be touched again: what changes
over time are the PLANS and the ROUTING TABLE, not this contract.

Audience: the operator of an aegis instance. You do not have to be the
author of aegis to read it. If you are an agent, section
[§10](#10-if-you-are-an-agent) tells you exactly what to run and what
never to invent.

---

## 0. Why it exists

Creating an organization today means six YAML files written by hand, two
secret ceremonies and a number of steps that live only in the head of
whoever has already done it once. That works once. It does not work for
a product where the author is just one more customer.

The problem is not the amount of YAML: it is that **there is nowhere
that says what an organization IS**. Each one came out looking like the
previous one by imitation, and the differences between them are not
decisions —they are accidents of when each one was created.

This protocol moves that into a one-file contract and a generator that
materialises it.

---

## 1. The model, in four sentences

An **organization** is a project: `veterinaria`, `pasteleria`,
`portafolio`. It lives in a namespace of its own, and it has its own
quota, its own network isolation and its own security boundary.

A **service** is a deployable piece inside an organization: a front end,
an API, a database, a worker. An organization has several.

The **platform services** are shared by every organization: the S3
storage (Garage), the AI substrate, the registry, the CI. Nobody
installs them per organization; you ask them for access.

The **contract** is one YAML file per organization. It is the only thing
written by hand.

```
orgs/veterinaria.yaml     ← contract (by hand)
        │
        │  aegis org apply
        ▼
k8s/organizations/org-veterinaria/…   ← generated
k8s/argocd-apps/tenants.yaml          ← generated (entry)
        │
        │  git commit + push
        ▼
    ArgoCD deploys
```

---

## 2. The inversion that makes this last

**The contract expresses INTENT. The platform imposes GUARANTEES.**

A contract cannot ask for less security than the platform demands today,
nor be exempt from what it will demand tomorrow. When the floor rises,
it rises for every organization at once, without editing a single
contract.

Concretely, this is NOT configurable from a contract and never will be:

| Guarantee | Where it is imposed |
|---|---|
| Only images signed by this platform | Kyverno `require-aegis-signature`, scoped by namespace label |
| The organization cannot create cluster-scoped resources | AppProject `aegis-tenant-<org>` with `clusterResourceWhitelist: []` |
| All traffic denied except what is granted | NetworkPolicy `default-deny` in every namespace |
| Every container declares `limits` | The namespace's ResourceQuota |
| Secrets travel encrypted in git | SOPS + age, KSOPS at deploy time |

A contract asks for *access to the bucket* or *two AI tasks*. It does
not ask to "turn signature verification off". That option does not exist
in the schema, which is the only way for it never to exist.

**Corollary for the generations.** An organization created under
contract v1 keeps working when the platform reaches v3, because what
ages is the RENDER (which the generator maintains per version) and not
the guarantees (which apply to all alike). See
[§8](#8-versions-and-migration).

---

## 3. The contract

One file per organization, in `orgs/<name>.yaml` of the platform repo.

```yaml
# orgs/veterinaria.yaml
version: 1                      # MANDATORY. See §8.
organizacion: veterinaria       # [a-z][a-z0-9-]{2,30}. Namespace = org-<name>.
dominio: veterinaria.__ROOT_DOMAIN__

# Quota: a NAMED PLAN, never loose numbers.
# The numbers live in platform/plans.yaml and can be readjusted for
# every organization at once. If `cpu: 4` were written here, thirty
# files would have to be edited the day the hardware changes.
cuota: pequena                  # pequena | mediana | grande

almacenamiento:
  bucket: true                  # a bucket of its own in the shared Garage

ai:
  plan: basico                  # basico | estandar | intensivo
  tareas:
    # The organization names a CAPABILITY, never a model and never a
    # provider. See §5.
    - {nombre: chat.recepcion, capacidad: chat.rapido, prompt: recepcion.txt}
    - {nombre: npc.mascota,    capacidad: chat.rapido, prompt: mascota.txt}

servicios:
  - nombre: front
    tipo: estatico              # nginx serving a build
    repo: github.com/ORG/veterinaria-front
    publico: /                  # path under `dominio`
    # NO `tamano`: a static front takes the default, `chico`.
    # NO `usa`: a static front end has nowhere to keep a credential.
    # Whatever needs AI or the bucket goes behind the `http`.
  - nombre: api
    tipo: http
    repo: github.com/ORG/veterinaria-api
    puerto: 8080
    publico: /api
    tamano: mediano             # chico | mediano | grande. Never a number.
    usa: [bucket, ai, postgres] # explicit network grants
  - nombre: db
    tipo: postgres              # the platform provides it: no repo
  - nombre: recordatorios
    tipo: worker                # it does not listen: it processes
    repo: github.com/ORG/veterinaria-cron
    usa: [postgres]
```

### What each `tipo` means

A type that restricts nothing is not a type, it is a label. Each one
narrows down which fields make sense, and the generator **rejects** the
ones that do not:

| tipo | who brings it | `puerto` | `publico` | `usa` |
|---|---|---|---|---|
| `estatico` | the tenant's repo | ✗ (the platform serves on 8080) | **mandatory** | ✗ **forbidden** |
| `http` | the tenant's repo | **mandatory** | optional | optional |
| `worker` | the tenant's repo | ✗ | ✗ | optional |
| `postgres` | **the platform** | ✗ (5432) | ✗ never | ✗ |

Of them all, the only one that is about **security** and not about
coherence is `estatico` without `usa:`. A static front end has no server
side: every byte handed to it travels to the browser, so a credential
there is a published credential. Whatever needs to talk to the AI or to
the bucket goes behind an `http` — which is exactly the BFF's role, and
what the portfolio's and the blog's contracts already say in a comment.
Now the generator says it too.

`postgres` is the first type **provided by the platform**: it carries no
repo, and its image (signed, by digest), its disk and its credential
come out of `services.yaml`. One database per organization, never
shared — a `DROP` in one cannot touch its neighbour.

`aegis dev test-types` walks every rule with its counter-example and
demands that the generator reject it **naming the right reason**: a
rejection for the wrong reason would come out green all the same, and
that is a mistake already made four times this week.

### What a service asks for: `tamano`

`cuota` is the ceiling of the WHOLE organization. `tamano` is how much
of it each service takes. They are two different walls and this is the
one that was missing until 2026-08-29.

What was there before: the resources of a service lived in the
Deployment of the tenant's own repo, and the canonical template asked
for `50m`/`32Mi` with a ceiling of `200m`/`64Mi`. Those numbers are
right for a compiled binary and they **kill a JVM during start-up** —
the pod is OOM killed, the event names memory, and nothing points back
at the template. Meanwhile the only thing the platform controlled was
the namespace quota, which is too coarse to keep one service from
eating another's share.

| `tamano` | what it is for |
|---|---|
| `chico` | a compiled binary — Go, Rust — or a static front served by nginx |
| `mediano` | a JVM, or an interpreter with its dependencies loaded |
| `grande` | something that really works: it holds connections, keeps a cache, moves uploads |

**It carries no numbers, by the same rule as `cuota`.** The four figures
of each step — what it reserves and what it caps, of CPU and of memory —
live in `plans.yaml`. If `memoria: 512Mi` were written here, resizing
thirty organizations would be a migration instead of one edit. It is
also why re-tuning a step is **not** a new version of the contract (§8):
the contract names no number, so it cannot fall out of date because of
one.

**The default is `chico`**, and it exists so that adding this field was
not a migration: every contract written before it goes on validating and
renders exactly as it did. A `postgres` **rejects** `tamano` — what a
service the platform provides asks for is decided by `services.yaml`,
along with its image, its port and its disk, and a field that would be
ignored is worse than one that is refused.

**If the sum does not fit, the generator refuses and shows the
account.** It adds up every service's declared size — plus what the
platform provides, the database included — and compares it with the
plan's quota:

```
✗ the services of this organization do not fit in its quota plan.

  requests.memory
    the services ask  api (grande) 1024Mi + datos (postgres, provided
                      by the platform) 256Mi + front (grande) 1024Mi
                      = 2304Mi
    plan `pequena` gives    2048Mi

  TWO WAYS OUT, and they are the whole list:
    · raise the organization's `cuota` (try: mediana, grande)
    · lower some service's `tamano` (grande -> mediano -> chico)
```

The arithmetic is written out on purpose. Left to the cluster, the same
mistake arrives as a `ResourceQuota` rejecting whichever pod happened to
be scheduled last, hours later, in a message about millicores — and
whoever reads it has to redo this sum by hand to find out whether the
answer is a bigger plan or a smaller service. The count is **one replica
per service**: the contract has no `replicas` field, so this is the
floor. The quota is still the wall that actually holds; this is the
warning that gets there first.

**What comes out of it in the cluster**, and it is two objects with two
different jobs:

- a **LimitRange** in the namespace, carrying the default step. It fills
  in what a container did not declare. With a `ResourceQuota` over
  requests and limits, a container that declares no resources is
  *rejected* by the apiserver with a message that names the quota and
  never the Deployment that forgot the block; this turns that rejection
  into a default.
- a **namespaced Kyverno `Policy`**, one rule per service, that fixes
  requests and limits to what its `tamano` asks for. It patches the
  **Pod** and never the Deployment: the Deployment is what ArgoCD
  compares against git, and mutating it would leave desired ≠ live
  forever — whose obvious way out, `ignoreDifferences`, switches
  auto-sync off (#36). Pods come from no git, so there is no drift to
  produce.

### The schema's rules

1. **Unknown fields = error.** They are not ignored in silence. A typo
   in `almacenamineto:` has to fail loudly, not turn the bucket off
   without saying so.
2. **No infrastructure numbers.** No CPU, no memory, no tokens per
   minute, no replicas. All of that is a named plan.
3. **No model names and no provider names.** See §5.
4. **`usa:` is an allowlist.** A service that does not declare `bucket`
   cannot reach the Garage — not by convention, but because the
   generated NetworkPolicy does not let it.
5. **The name is immutable.** Changing it does not rename: it creates
   another organization. The generator detects that and says so.

---

## 4. The generator

```
aegis org apply orgs/veterinaria.yaml      # renders into git
aegis org apply orgs/*.yaml                # all of them
aegis org plan    orgs/veterinaria.yaml      # shows the diff, writes nothing
aegis org delete  veterinaria                # see §7
```

**The generator does NOT talk to the cluster.** It has no `kubectl` on
its path. It writes files in the repo and stops. What deploys is ArgoCD,
after you have reviewed the diff and committed. This is not purism: it
is what makes an `aegis org apply` safe to run at any moment, even
wrongly, because the worst that can happen is an ugly diff you do not
commit.

### What is DERIVED from all the contracts

Besides each organization's directory, the generator re-derives eight
files that depend on the SET — not on the contract you have just
touched:

| File | What comes out of it |
|---|---|
| `tofu/envs/cloudflare-tunnel/main.tf` | the edge's `public_hostnames` |
| `k8s/base/ai-system/routes.yaml` | the organization → AI plan map |
| `k8s/bootstrap/appprojects-tenants.yaml` | the AppProject of every organization that has a repo |
| `k8s/base/platform/argocd-secrets/secret-generator.yaml` | the deploy key ArgoCD reads each repo with |
| `k8s/argocd-apps/tenants.yaml` | the Application that deploys each organization |
| `k8s/base/garage-system/aprovisionar.yaml` | one Job per organization that asked for a bucket |
| `k8s/base/garage-system/kustomization.yaml` | whether `aprovisionar.yaml` is wired in or not |
| `k8s/base/garage-system/secret-generator.yaml` | the S3 credential mirrors that KSOPS decrypts |

#### The AppProjects (2026-08-05, #19)

The AppProject **is** an organization's permission boundary: which repo
it may read from, which namespace it may write into, and the fact that
it may not touch anything cluster-scoped. It is derived **only for the
contracts that declare a repo**: an organization of pure infrastructure
has no external Application at all, and a project without `sourceRepos`
narrows nothing.

It was derived because of two things that were measured, not out of
tidiness:

1. **One was missing.** `org-ejemplo` had a contract and no project. The
   moment it declared `repo:`, its Application would have sat in
   *project not found* — an error that arrives late, after the repo, the
   pipeline and the push.
2. **Repeated blocks drift.** `aegis-tenant-canary` was the only one of
   the four tenant projects without `orphanedResources`: it was left out
   when #31 added it to the other three. The real consequence: the
   canary's app was never evaluated and `aegis check` counted it inside
   *"nothing orphaned"*. **A block copied three times gets updated
   twice.** Derived, the blocks are identical by construction and not by
   discipline.

What is **not** derived and stays by hand in
`k8s/bootstrap/appprojects.yaml`: `aegis-bootstrap` and `aegis-platform`
(they belong to the substrate, not to any organization),
`aegis-tenant-canary` (the canary belongs to the platform: it proves the
tenant path works, so it cannot depend on that path) and
`aegis-tenant-ecommerce` (inherited, same criterion as
`tenants-heredados.yaml`).

**ArgoCD does NOT apply these**, on purpose (W-06 / R1-B): `kubectl`
applies them in phase 35, before root. That avoids the
AppProject-versus-Application race inside a single sync, and it closes
the privilege-escalation vector of an App that edits projects. As a
consequence, signing an organization up takes one extra step:

```
kubectl apply -f k8s/bootstrap/appprojects-tenants.yaml   # BEFORE
aegis sync root                                           # AFTER
```

The generator prints it every time it rewrites the file. And the
invariant «every Application references a defined AppProject» is checked
by `aegis verify` (check 76) against the repo, with no cluster: what is
verified is that references ⊆ definitions, not a list of names — a list
would be a fifth place to remember.

#### The repository deploy key (2026-08-05, #48)

ArgoCD needs a credential to read a private repo, and that credential
belongs to the organization even though the Secret lives in ArgoCD's
namespace: it comes out of its `repo:` and it disappears with it.

It was in the worst possible state. The two that existed —blog and
portfolio— had been written by hand with `sops`, **nobody produced
them**, no protocol documented them and the rotation checklist did not
name them. The symptom shows up on a fresh instance: there the age key
is a different one, the init re-encrypts everything it does produce, and
these two stay encrypted with a key that no longer exists. KSOPS cannot
decrypt them and the `argocd-secrets` App never syncs.

Now `aegis secret create <contract>` creates them in the same pass as
the rest of the organization's secrets, and the generator merely lists
them. The material is generated with `ssh-keygen` in tmpfs and wiped
with `shred` — the same mechanism the init uses for the age key itself.

**One manual step remains, and it is irreducible:** the PUBLIC half has
to be registered on GitHub. The command prints it and says what to do:

```
<repo> → Settings → Deploy keys → Add deploy key
title: aegis-argocd-ro       NO "Allow write access"
```

No write access, and that matters: ArgoCD only READS. A deploy key with
write access lets whoever holds the cluster write into the app's repo,
which is the wrong direction.

Two of the eight are garage's **wiring**, and they are derived because
of what happened on 2026-08-04: they were written by hand, and the
generator was writing two files inside `garage-system/` that neither of
them listed — `aprovisionar.yaml` and `secret-garage-<org>.enc.yaml`.
The symptom was the worst possible one: `apply` said everything had gone
fine, the files stayed in git, and nothing happened in the cluster. No
error, anywhere.

**A generated file that nobody lists is a file that does not exist.** If
the generator writes into a directory, it has to derive that directory's
wiring too — or the wiring has to be a glob, and globs are forbidden by
A7 for secrets.

The same run sweeps away the mirrors that are left over: if an
organization is deleted, or you take the bucket out of its contract, its
`secret-garage-<org>.enc.yaml` disappears from `garage-system/`. Mind
what that means — deleting it from the repo **does not revoke the key**
in Garage; that is `garage key delete` against the store.

The eight run **always**, at the end of `plan`, `apply` and `delete`.
They are not subcommands you have to remember to run: remembering is
exactly what already failed twice with the edge. And they run over ALL
the contracts, because signing an organization up changes the whole set
— its hostname, its plan and its Application appear or disappear on
their own.

The case this closes is the worst of all: before, `tenants.yaml` was
edited by hand. Forgetting gave you **everything generated, everything
committed and nothing deployed**, without a single error in sight.

The organizations that predate the generator live in
`tenants-heredados.yaml`, by hand and on purpose: mixing them into the
generated file would make the next run delete them in silence.

### The idempotence rules

They are the heart of the protocol. Without them "idempotent" is just a
word.

**I1 — Same contract, byte-for-byte identical output.** No timestamps,
no UUIDs, no map ordering that depends on the interpreter. Running twice
in a row leaves the git tree clean the second time. It is verifiable and
the CI verifies it.

**I2 — Secrets are created if they are missing and are NEVER
regenerated.** An `aegis org apply` over a live organization rotates no
credential. Rotating is a deliberate act and it has its own command:
`aegis secret rotate <file.enc.yaml>`.

(Until 2026-08-23 this line read «aegis org rotar» (with no backticks
here, deliberately: in this document backticks are invocations, and
check 106 verifies them one by one), a command that NEVER EXISTED.
Whoever typed it got no useful error but an «invalid subcommand», and
the natural conclusion is «I got it wrong», not «the document is
stale». It was found by check 106, which extracts every cited
invocation out of the documents and demands that it exist: the documents
the operator executes are code in another syntax, and they age exactly
the same.) Without this rule nobody dares run the generator twice, and a
generator that frightens people is not idempotent even when it is.

**I3 — Generated files carry a banner and a hash.**

```yaml
# GENERATED BY `aegis org` — DO NOT EDIT BY HAND
# contract: orgs/veterinaria.yaml
# hash: sha256:3f9a…   (of the contract that produced it)
```

If the file was changed by hand, the hash does not match and the
generator **refuses and shows the difference**, instead of overwriting
it. The output is the contract, not the file.

**I4 — Convergence, not accumulation.** Taking `bucket: true` out of the
contract and reapplying REMOVES the bucket's NetworkPolicy. The
generator owns the organization's whole directory.
Inherited warning: **removing a resource from git does not remove it
from the cluster** (`prune` omitted, A19). That is why `aegis org apply`
says explicitly which files it deleted and what has to be done about
them. See §7.

**I5 — An invalid contract produces nothing.** It is validated whole
before the first file is written. Never a half-generated tree.

### What it emits

```
k8s/organizations/org-veterinaria/
  bundle.yaml            Namespace (with the enforce label), ResourceQuota,
                         LimitRange with the default `tamano`, the Kyverno
                         Policy that fixes each service's size, default
                         ServiceAccount with regcred
  appproject.yaml        AppProject aegis-tenant-veterinaria, cluster-scoped []
  netpol.yaml            default-deny + the grants the contract asked for
  apps.yaml              one ArgoCD Application per service
  secret-*.enc.yaml      ONLY if they are missing (I2)
  kustomization.yaml
k8s/argocd-apps/tenants.yaml    the organization's entry
```

And, if the contract asks for them, two registrations on the platform:

- the AI tasks in the gateway's registry,
- the bucket and its credential in the Garage.

---

## 5. AI: capabilities, plans and providers

This is the piece designed so that adding Vertex, Bedrock or a third
party's credits **touches no organization**.

### The organization asks for a CAPABILITY

```yaml
ai:
  plan: basico
  tareas:
    - {nombre: chat.recepcion, capacidad: chat.rapido, prompt: recepcion.txt}
```

A capability is a promise about behaviour: *chat.rapido* means "answers
within a few seconds, short context". It does not say with what. An
organization that named `qwen3-4b` would be married to an infrastructure
decision that is not its own, and the day that model is replaced every
single one of them would have to be edited.

Capabilities of contract v1:

| Capability | Promise |
|---|---|
| `chat.rapido` | conversational reply, short context, low latency |
| `chat.largo` | wide context, higher latency tolerated |
| `embeddings` | vectors for semantic search |
| `transcripcion` | audio to text |

### The platform decides WITH WHAT

`platform/ai/routes.yaml`, a platform plane, outside the organizations'
reach:

```yaml
capacidades:
  chat.rapido:
    proveedor: local
    modelo: qwen3-4b
    contexto_max: 12288
  chat.largo:
    proveedor: local
    modelo: qwen3-4b
    contexto_max: 12288

# The day a third party's credits exist, this is ALL the change:
#
#   chat.largo:
#     proveedor: vertex
#     modelo: gemini-x
#     credencial: secret-vertex-veterinaria   # or a platform one
#     contexto_max: 1000000
#
# Zero organizations touched. Zero contracts migrated.
```

**Provider rule:** a new provider is added by implementing the gateway's
interface (generate, with streaming and with a budget cut-off). It is
not added by dropping an `if` into the request path.

**Cost rule:** a paid provider has its budget in the SAME currency as
the local one — tokens, not requests — so that a change of routing does
not change what a plan means. A `basico` plan costs the user the same
whether what sits behind it is a GPU of our own or an invoice.

**Only what can actually be served is declared.** `ai/routes.yaml`
carries no capabilities "reserved for later". The gateway rejects at
STARTUP a provider with no implemented client, and `aegis org` takes the
list of capabilities a contract may name out of this file. A capability
declared in advance would be a valid contract that blows up only when a
visitor invokes it: the error would show up far away from its cause,
which is the most expensive way to be wrong.

> The previous version of the generator had the capability list written
> by hand and it included `embeddings` and `transcripcion`, which still
> have no engine. A contract that asked for them passed validation and
> then kept the gateway from starting.

### How it reaches the gateway

The gateway reads none of these files: it reads a ConfigMap. `aegis org`
**generates** it by combining three sources, and that is why the
organization→plan map is written by hand nowhere.

```
ai/routes.yaml   ─┐
platform/plans.yaml ─┼─→  k8s/base/ai-system/routes.yaml  (ConfigMap ai-ruteo)
orgs/*.yaml     ─┘                    ↓  mounted at /etc/ai-ruteo
                                  ai-gateway
```

| Source | Contributes | Who edits it |
|---|---|---|
| `ai/routes.yaml` | `capacidades` | the platform |
| `plans.yaml` | `planes` | the platform |
| `orgs/*.yaml` (`ai.plan`) | `tenants` | each organization |

It is regenerated **always**, at the end of `aegis org plan` and
`aegis org apply`, just like the edge, and for the same reason: signing
an organization up changes the whole map, not just its row. If you had
to remember to run a separate command, the symptom would be a gateway
that starts without knowing about the organization just created — and an
unknown tenant falls to the smallest plan, in silence.

The map's key is the **namespace** (`org-portafolio`), not the
contract's short name: it is what the gateway receives in the API key.

### The plans

`platform/plans.yaml`:

```yaml
ai:
  basico:    {tokens_min: 600,   concurrencia: 2, prioridad: 3, reserva: 0.15}
  estandar:  {tokens_min: 4000,  concurrencia: 2, prioridad: 2, reserva: 0.25}
  intensivo: {tokens_min: 12000, concurrencia: 4, prioridad: 1, reserva: 0.35}
```

Four numbers, and each one bounds something different:

| Field | What it bounds | Scope |
|---|---|---|
| `tokens_min` | output budget | **organization** |
| `concurrencia` | its own requests on the GPU at once | **organization** |
| `prioridad` | who gets woken first (lower = sooner) | plan |
| `reserva` | fraction of the quota that is guaranteed | **plan** |

`prioridad` is what orders the queue when there is contention: with a
single GPU behind it, two organizations asking at the same time have to
be resolved somehow, and "first come, first served" punishes whoever
pays more.

`reserva` is the counterweight, and it is what keeps that from
degenerating into exclusivity: however low the plan, that fraction of
the quota is always kept for it. **A high plan buys latency, not the
right to leave somebody else without a turn.**

**The reserve is per PLAN and not per organization.** If it were per
organization, ten of them on the smallest plan would each reserve their
fraction and the quota would not be enough for any of them. Per plan,
the set of `basico` tenants shares its portion — which is what the word
means. `concurrencia` IS per organization, because what is bounded there
is one concrete organization.

An implementation detail worth knowing: a fraction that rounds down to
zero slots is raised to **one**. A declared reserve that reserves
nothing is not a reserve, and with small quotas (4 slots) any fraction
below 0.25 would land there. If the sum goes over 100%, they are all
scaled down proportionally instead of failing — a badly summed routing
must not be able to keep the gateway from starting.

**The numbers live here and nowhere else.** Readjusting them means
editing one file, not thirty. The CPU/memory quotas live in the same
file under `cuota:`, with the same named steps.

---

## 6. Secrets

Each organization needs, depending on what it asks for:

| Secret | When | Origin |
|---|---|---|
| `regcred-internal` | always | read credential for the internal registry |
| `ai-gateway-key` | if there is an `ai:` | `aegisk_…` key issued by the gateway |
| `garage-<org>` | if there is a `bucket:` | the S3 key pair of its own bucket |

```
aegis secret create orgs/veterinaria.yaml   # creates the ones that are missing
aegis secret rotate <file>                  # deliberate, one at a time
```

`aegis org` does **not** create secrets: it writes manifests and handles
no cryptographic material. Separating the two is what makes it possible
to run the generator without thinking twice about it. When any of them
is missing, it lists it together with the exact command to create it.

Rules, all of them consequences of I2:

1. **Create if missing, never overwrite.** Reapplying does not rotate.
   It is a mechanism, not a promise: `aegis secret` over a file that
   already exists says "not touched" and exits.
2. **The operator does not see the material.** It is generated with
   `secrets` (not `random`, which is a predictable Mersenne Twister),
   handed to `sops` **through stdin**, and the only thing that touches
   disk is the encrypted file. It does not pass through `argv`, and it
   does not pass through a readable temporary file.
   Encrypting **does not need the private age key**, only the public
   recipient from `.sops.yaml`: creating credentials never forces you to
   materialise the key that decrypts everything.
3. **Never in `argv`.** Neither locally nor remotely. Through stdin, or
   through a file with 600 permissions (rule A27 of the init).
4. **Verified by result, not by reading.** The check that a secret came
   out right is that the pod starts and authenticates, not that somebody
   printed it. There is a recorded incident about this:
   `ai-tenant-key.md` §3 documents a check that answered "OK" by reading
   the first character of an error message.
5. **Rotating is a separate command**, deliberate, with a log of its
   own. `aegis secret rotate` goes one file at a time and is
   incompatible with the bulk `create`: rotating in bulk is how you end
   up rotating something you did not mean to rotate.

**What rotating does NOT do.** It generates the new credential and
nothing else. The old one stays valid wherever it is accepted: rotating
`ai-gateway-key` revokes nothing until the entry is removed from
`secret-ai-keys.enc.yaml` — a file shared between organizations, which
is precisely why it is not edited on its own. The command says so while
rotating, in red.

---

## 7. Deleting an organization

```
aegis org plan-delete veterinaria    # shows everything, touches nothing
aegis org delete      veterinaria
```

Today this is the protocol's weakest point, and it is better said than
discovered: **`prune` is omitted across the whole platform (A19)**, so
removing files from git removes nothing from the cluster.

That is why `delete` does two separate things, in this order:

1. It removes the contract and the generated files. That is git, and it
   is reversible. The three derivations (edge, routing, `tenants.yaml`)
   run afterwards, so its hostname, its plan and its Application
   disappear **on their own** — they come out of the contracts, not out
   of separate lists.
2. It **prints** the exact commands to withdraw whatever is still alive,
   and it does not run them.

It does not run them because deleting a namespace takes the data with
it, and that cannot happen through a command somebody ran with a
mistyped name. The day #31 is resolved, step 2 can become automatic with
a confirmation.

Step 2's commands come out ordered from least to most destructive, and
**the Applications go first**: as long as they live, they reconcile and
recreate whatever you delete. Their names are derived from the contract,
not eyeballed — that is precisely the step where a hand-typed name
deletes the organization next door.

Two warnings that the command prints, because they are the ones
discovered late:

- **Deleting an `.enc.yaml` revokes nothing.** The credential stays
  valid wherever it is accepted. Revoking is part of step 2, and it goes
  before deleting the file if you want to be able to audit it
  afterwards.
- **PVCs can outlive the namespace**, depending on the `reclaimPolicy`.
  It is checked afterwards, which is when it shows.

Two things are left by hand on purpose, because they live in SHARED
files that the generator does not govern: the `<org>.*` tasks of the AI
registry, and the organization's entry in `secret-ai-keys.enc.yaml`.
Editing them automatically would mean that a mistyped `delete` touches a
file belonging to every organization.

The **AppProject** was the third one until 2026-08-05 (#19) and is not
any more: `appprojects-tenants.yaml` is a derived file, so the
organization's document disappears on its own in the same run. What is
left to the operator is **applying** the file — ArgoCD does not manage
the AppProjects on purpose, and deleting them from the repo does not
take them out of the cluster (the same rule A19 that holds for
everything else):

```
kubectl apply -f k8s/bootstrap/appprojects-tenants.yaml
kubectl delete appproject -n argocd aegis-tenant-<org>
```

---

## 8. Versions and migration

`version:` is mandatory and the generator **rejects what it does not
know**. A contract without a version is not "v1 by default": it is an
error.

- The generator keeps one renderer per version. A v1 contract keeps
  rendering the same way even once v2 exists.
- A new version is justified only if the CONTRACT changes. Changing a
  plan's numbers, adding a capability or changing the routing are **not**
  a new version: that is exactly why they live outside.
- Migrating is explicit: `aegis org migrate orgs/veterinaria.yaml --to 2`
  rewrites the contract and shows the diff. Never automatic on apply.
  **Today only v1 exists and the command says so** instead of
  pretending: asking for a version that does not exist fails naming the
  ones that do. It exists already, and not as a TODO, because the
  mandatory `--to` is what prevents the bad alternative — somebody
  bumping `version: 2` by hand and finding out late that the generator
  had nothing new to do with it.
- The guarantees of §2 apply to every organization whatever its version.
  An old contract is not an old permission.

---

## 9. How this is proven not to be a fantasy

A protocol nobody has run is a wish. The acceptance tests, in order of
hardness:

1. **Reproduce what already exists.** Write the contract for
   `org-portafolio` —which today is hand-written and deployed— and check
   that the generator produces the same thing that is running. If it
   does not reproduce it, what is wrong is the model, not the
   organization.
2. **Real idempotence.** `apply` twice in a row leaves the tree clean
   the second time. The CI verifies it, not a person.
3. **Onboarding end to end.** A new contract all the way to a `curl`
   with TLS against the deployed service, with no manual step outside
   the commit.
4. **The floor holds.** In the new organization, an unsigned image is
   REJECTED by admission, and a pod of its own cannot reach another
   organization. It is proven by exercising the invariant, not by
   reading the YAML —the lesson of `aegis check` and of Disease B.
5. **Deleting and creating again** leaves the system as it was at the
   start.

---

## 10. If you are an agent

These rules exist because an agent with a `kubectl` at hand tends to fix
the symptom.

**Do:**
- Read the contract before touching anything. The truth is in
  `orgs/*.yaml`, not in the cluster.
- For any change to an organization: **edit the contract and reapply.**
  Always.
- Show the diff before committing.
- If the generator refuses because of the hash (I3), show the difference
  and ask. Do not overwrite it.

**Do not:**
- Do not edit files that carry the **GENERATED BY `aegis org`** banner.
  What has to change is the contract.
- Do not apply an organization's manifests with `kubectl apply`. The
  path is git → ArgoCD. A direct apply gets overwritten on the next sync
  and, in the meantime, it lies about the real state.
- Do not invent plan or quota values. If the one that is needed does not
  exist, the change is to add a plan in `platform/plans.yaml` and say
  so.
- Do not rotate secrets "just in case". Rotating is deliberate (§6.5).
- Do not put model names or provider names in a contract (§5).

**Verify by result, not by reading.** "The YAML says the signature is
required" is not a verification. Pushing an unsigned image in and
watching it bounce is.

---

## Implementation status

This document defines the contract. What is left to build is in tasks
#39–#43. The contract is considered closed; what gets adjusted along
with the implementation are the plans, the routing and the service
types — all of it outside this file on purpose.
