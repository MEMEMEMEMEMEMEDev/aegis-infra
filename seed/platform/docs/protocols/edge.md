# Protocol: the edge

How a hostname comes to exist on the internet, and why nobody writes it
by hand.

---

## 0. The problem it solves

A public aegis hostname used to need **three** things, in three places:

1. `dominio:` in the organization's contract,
2. an entry in `public_hostnames` of `main.tf`, by hand,
3. somebody to run `tofu apply`.

Steps 2 and 3 depended on a person remembering. And the failure mode is
the worst one there is: **if it is missing, the hostname simply does not
exist**. No error, no alarm, nothing red. The cluster's IngressRoute is
perfect and nobody arrives.

It has already cost twice:

- `ai.__ROOT_DOMAIN__` was declared in `main.tf` and never applied (task
  #35). The gateway was running, its traefik route existed, and the
  hostname did not resolve.
- `blog.__ROOT_DOMAIN__` had to be remembered and added on 2026-08-03.

---

## 1. How it works now

```
orgs/veterinaria.yaml           edge.yaml
  dominio: vet.ejemplo.com        platform: [aegis, argocd, jenkins,
                                            grafana, ntfy]
         │                        root_domain: ejemplo.com
         └────────────┬───────────────────┘
                      ▼
               aegis org apply
                      │
                      ▼
   main.tf: public_hostnames = ["aegis",…,"vet"]   ← GENERATED
                      │
                      │  git push
                      ▼
      the operator runs tofu-apply.sh apply
                      │
                      ▼
            the CNAME exists in Cloudflare
                      │
                      ▼
         edge-chequeo job (daily, no age key)
                      │
        ┌─────────────┼─────────────┐
     exists        missing    not-evaluable
      (ok)          (red)        (yellow)
```

**Declaring `dominio:` in the contract is all there is to do.**

---

## 2. The derivation

`aegis org` computes the list as:

```
public_hostnames = edge.yaml:platform + [dominio of every orgs/*.yaml]
```

Rules:

- **ALL the contracts are read**, not only the one being applied. The
  list belongs to the whole instance; rewriting it out of a single
  contract would erase the others.
- The contract declares the **FQDN** (`vet.ejemplo.com`) because that is
  what a human recognises; tofu wants the **label** (`vet`), and the
  generator does the subtraction against `root_domain`.
- A domain **outside the zone** is an error, not one more entry: the
  edge can only create CNAMEs inside its own zone, and another zone is a
  decision, not a case.
- The order is stable: platform in declaration order, tenants
  alphabetically. Without that the diff changes with the filesystem and
  idempotence breaks (rule I1 of the organizations protocol).
- The derivation runs **always** at the end of `apply`, not as a
  separate command. Remembering to run a command is exactly what failed
  the two previous times.

The **platform**'s own doors (`aegis`, `argocd`, `jenkins`, `grafana`,
`ntfy`) come
out of no contract because they belong to no organization: they are the
substrate's own. They live in `edge.yaml`.

---

## 3. The guard

> **Historical.** This guard was designed for a job that applied on its
> own. Since #46 the job **does not apply** (see below for why), so the
> guard lives in the operator's head and not in an `if`. It is left
> written down because the criterion still holds, and because it is what
> to look at before typing `apply`.

The criterion is not "trust the pipeline", it is **what it can break**:

| Plan | What it means |
|---|---|
| `0 to add, 0 to change, 0 to destroy` | already converged, nothing to do |
| there are changes, **`0 to destroy`** | additive and recoverable — it gets applied |
| **any destroy at all** | **STOP AND READ**: deleting a CNAME takes a site off the internet |
| **many additions over a converged environment** | **there is no state**, there is no work |

The last row is the most important one and the least obvious. A plan
full of additions over something that should already be converged does
not mean "there is a lot to do": it means tofu **is not seeing the
state**, so everything looks new to it. Measured on 2026-08-03: the
first real build planned "9 to add, 0 to destroy" and the destroy guard
passed it as good. What saved it was a network error, not the design.

Details that matter:

- **The saved plan** (`plan.bin`) is what gets applied, not a fresh one.
  Between the plan and the apply the world may have changed; applying
  the binary guarantees that what runs is what the guard reviewed.
- `-detailed-exitcode` is used (0 no changes, 2 changes, 1 error)
  instead of interpreting the text.
- Stopping because of a destroy is **UNSTABLE, not FAILURE**: the job
  did its job well. There is a decision that belongs to a person, and
  that has to look different from "it broke".
- `disableConcurrentBuilds()`: two simultaneous applies over the same
  state are a race.

---

## 3.1 The state guard, which is the one that really matters

Before the plan, the job verifies that **there is state**. It goes first
because it is stronger than the destroy guard, and because the destroy
guard **is not enough on its own**.

A plan with additions over an environment that should already be
converged does not mean "there is work": it means **there is no state**.
And without state tofu sees nothing of what exists, so everything looks
like an addition to it and `0 to destroy` passes with honours while
duplicate resources are being created.

Measured on 2026-08-03, on the job's first real build:

```
Plan: 9 to add, 0 to change, 0 to destroy.
cambios=true destruye=false        ← the guard passed it as good
```

What saved it was a network error, not the design. Nine duplicate
CNAMEs.

**RESOLVED on 2026-08-04 (#46): the state travels ENCRYPTED AND
VERSIONED, and the edge's apply belongs to the operator.**

Before, the state lived only on the operator's machine and `*.tfstate`
was in `.gitignore`. That broke the project's identity —starting from
zero = recovering from a disaster = moving to another VPS—: a virgin
clone has no state, tofu sees nothing of what exists, and **everything
looks like an addition to it**. It would try to create the tunnel and
the six CNAMEs all over again.

Before deciding, a fact this very document had wrong had to be
corrected. It said the state contains "the tunnel's ID and the zone's
metadata". The file was read: it contains **`tunnel_secret` and the
Cloudflare token IN THE CLEAR**. That changes the question, because the
backend would not be keeping metadata but a platform secret.

| Where | Recovery | CI can apply | What it costs |
|---|---|---|---|
| Only on the machine | **broken** | no | the DR hole |
| Remote backend | ok | **yes** | `tunnel_secret` ends up behind a new credential |
| **Encrypted in git (chosen)** | ok | no | the apply is run by the operator |

The remote backend was ruled out for what it cost, not for the work
involved: whoever gets hold of that credential brings up their own
`cloudflared` and **receives the traffic of every hostname**. Today the
worst case of the Cloudflare token leaking is a compromised DNS zone
(§4, D6); that would become the entire traffic. Encrypting it with the
age key, by contrast, adds nothing new to look after: that key is
already the root of trust and is already needed in order to recover.

The instance's own Garage was ruled out because of the usual
circularity: recovering the cluster needs the edge, and the edge would
need the cluster.

**How it works.** `tofu-apply.sh` decrypts `terraform.tfstate.enc.json`
before running tofu and encrypts it again afterwards — but **only if it
changed**, because `sops` produces a different text on every run even
when the content is identical, and a diff that means nothing is a diff
people stop reading. The plaintext `.tfstate` is still ignored; the
encrypted one is not —`*.tfstate` does not reach it because it ends in
`.json`, checked with `git check-ignore`.

Verified by moving the plaintext state out of the repo and running the
wrapper: it decrypted the 5 resources, `state list` returned the 9
objects, and the `plan` gave **0 to add, 0 to destroy**. A virgin clone
converges without duplicating anything.

**What this costs, said to your face.** CI cannot apply the edge:
decrypting needs the age key and the age key does not enter CI (§4). The
`edge-apply` job was replaced by `edge-chequeo`, which does what really
motivated the original —that nobody find out too late that a hostname is
missing— without needing either the state or the key: it asks Cloudflare
what exists and compares that with what the contracts derive. See
`aegis edge check`, which also runs inside `aegis check`.

That check **does not read the state**, and not only because it could
not: the state says what tofu *believes* exists, and the only reason to
look is that the two can differ. A detector that reads the same file as
the applier detects nothing.

What the check does **not** cover, said just as plainly: it looks at the
zone's CNAMEs, which is exactly the failure of #35. It does not look at
the tunnel's ingress rules — a CNAME that exists with a tunnel that does
not route it gives a 404, and that is not visible from there. It is
recorded as a limit and not as "already covered".

Applying the edge is an operator's command, and with the derivation of
§2 there is nothing to remember beyond running it:

```
cd platform/tofu
SOPS_AGE_KEY_FILE=~/.config/sops/age/aegis.key \
  ./tofu-apply.sh -chdir=envs/cloudflare-tunnel apply
```

After applying, **commit the re-encrypted state**. Without that commit
the next recovery does not know that the new thing exists — the wrapper
warns about it on stderr on every run that modifies it.

## 4. The age key does not enter CI

This is the most important thing in the whole protocol.

The job receives **only the Cloudflare token**, as a Jenkins credential.
`tofu-apply.sh` takes the token from the environment if it is already
exported and decrypts nothing — the same rule that already held for
`account_id`, `zone_id` and `root_domain`, applied to the fourth value.

Why it can be done: **D6 shrank tofu's surface down to Cloudflare and
nothing else.** No Kubernetes resources, no GitHub, no PKI. A single
token, from a third party, rotatable without ceremony.

Why it matters: the worst case of that token leaking is **a compromised
DNS zone**. With the age key in there, the worst case would be *the
whole platform* — every secret in the repo is decrypted with it.

The `aegis-ci-tofu` image **does not carry sops**, on purpose and
forever. If some day somebody needs sops in that container, the right
question is why CI is decrypting something, not how to add the tool to
it.

---

## 5. What is still manual, and rightly so

- **A plan with a destroy.** By design (§3).
- **Changing the Cloudflare zone or account.** That is a migration, not
  an operation.
- **The first bootstrap.** Phase 25 of the init already runs
  `tofu apply -auto-approve` by itself; this job covers what comes
  afterwards.

---

## 6. If you are an agent

- To publish a hostname: **edit `dominio:` in the contract** and
  reapply. Do not touch `main.tf`.
- If you see a `public_hostnames` with a value that comes out of no
  contract, somebody wrote it by hand and the next `aegis org apply`
  will delete it without warning. Take it to the contract.
- Do not add sops or the age key to `aegis-ci-tofu` (§4).
- A hostname that "does not work" has three possible layers, and it is
  worth ruling them out in this order, because they fail differently:
  1. `getent hosts <fqdn>` — if it does not resolve, the CNAME is
     missing (tofu).
  2. it resolves but gives a 404 — the IngressRoute is missing (the
     app's repo).
  3. it resolves and gives a 502/503 — the Service or the pods
     (cluster).
