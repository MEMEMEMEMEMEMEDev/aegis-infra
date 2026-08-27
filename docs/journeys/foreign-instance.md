# The foreign instance — rehearsing aegis on a machine that is not yours

The house machine is where aegis was written, and it is the worst
place to find out whether aegis installs. Its product repo and its
instance directory were one folder for a year; every earlier run left
something in it; the operator's accounts, keys and domain were baked
into the shape of things. The first time the artifact ran on a clean
machine, with a fresh GitHub account and no domain, it found about
thirty defects in one day that 136 static checks had not seen —
because they were not defects of the code; they were defects of the
distance between the product and its first instance.

This document is the rehearsal, written so that it can be repeated:
what travels, what is answered, what is measured, and what the
machine taught. `platform/docs/failure-modes.md` has the classes
(Diseases E to H were named that day).

## 1. The shape of the rehearsal

- A throwaway Linux host (4 CPU / 16 GB is enough; a 4-CPU node is
  also where the reservations problem shows). Nothing on it but ssh.
- A fresh GitHub account: the init creates and OWNS the repos it
  needs (`aegis-platform`, `aegis-canary`), and every tenant repo of
  the rehearsal is a lab copy under that account.
- `EDGE=local`: no Cloudflare account, no zone. Names resolve through
  sslip.io to the host's loopback; TLS comes from the instance's own
  CA. Everything the cloudflare profile has and local does not is
  declared as a gate without a subject — recorded, not silent.
- The product travels as a **git bundle** (`git bundle create x.bundle
  --all`), not through a remote the new account cannot reach: clone
  it, and `origin` is the file — a newer bundle plus `git pull`
  updates the product in place.

## 2. The customer's sequence

    aegis preflight                    # then: gh auth login, git identity, preflight again
    tmux new -s aegis
    aegis init                         # the wizard: EDGE=local, 127.0.0.1, defaults
    aegis check                        # no MAL; local's sections say "not evaluated (EDGE=local)"
    aegis verify --profile both        # the product verifies where it runs

When a phase fails, it is a bug of the product: fix it in the product,
ship a new bundle, `git pull`, and `aegis init --from <phase>`. That
loop ran fourteen times on the first day.

**Tenants.** Contracts go to `orgs/` with `dominio: <org>.<root>`
(under the root, or the edge refuses it) and `repo:` pointing at the
lab copies; then, in the order the organization protocol prescribes:
`aegis org apply`, `kubectl apply -f k8s/bootstrap/appprojects-tenants.yaml`,
`aegis secret create <contracts>`, commit and push, `aegis sync root`,
`aegis app apply <contracts>` (deploy keys; webhooks are "not
evaluable" under local — Jenkins polls instead). The lab copies of
existing repos need `ci/write-digest.mjs` (what the platform's
Jenkinsfile runs) and, for now, a per-namespace copy of
`regcred-internal` (`aegis secret move`, with the instance's age key).
Their `FROM` lines still name the bases of the machine they came
from: `aegis ci build base-images` propagates this instance's digests
into every consumer `aegis org apply` derived — that stage is the
mechanism, not a manual bump.

**Data.** A data bundle from another instance is encrypted to THAT
instance's age key, and the key does not travel. Decrypt it where it
was made and re-encrypt it to this instance's public key
(`.age-public`); `aegis data restore <bundle> --org <org>` then
detects that the database credential differs (it stores a fingerprint,
never the password) and refuses without `--force`. After `--force` the
restored database expects the OLD password: set the role's password to
the live Secret's value inside the database pod (through stdin, never
argv) and restart the consumers. Object storage is not restored yet;
the bundle carries it, and the restore says so.

**State.** `aegis state backup` proves its own roundtrip; `aegis state
restore` into another `AEGIS_HOME` proves the restore.

**Destroy and re-init.** `aegis destroy --yes --k3s` removes the
cluster and the host bridge and leaves, on purpose, the instance's
`platform/`, store and conf (the GitHub repos too: they carry the
init's marker topic, and deleting a repo is a decision taken by hand).
`aegis init --reset-state` over that host converges in minutes, and
inherits every stale thing `platform/` holds — Disease G in the
catalogue lists them and what the init now does about each. What it
does not do, the operator does after: `aegis org apply orgs/*.yaml`
and `aegis sync garage`, and the tenants rebuild through their
pipelines.

## 3. What it measured, in one table

| what | how it was measured | the day's number |
|---|---|---|
| the init on a clean host | `aegis init`, fourteen resumes | 15 phases, 174 gates pass, 20 without a subject |
| the product on the instance | `aegis verify --profile both` on the host | all pass, both profiles |
| the supply chain | signed canary admitted; unsigned image refused citing the policy; mirror and watch at zero fixable CVEs | end to end |
| tenants with data | two organizations from lab copies, catalogue served over HTTPS | 12 products, 4 orders |
| state | backup roundtrip, restore into a second home | both states |
| re-init on a dirty host | `destroy --k3s`, `init --reset-state` | complete, after three fixes |

## 4. What stays open (measured, not assumed)

- A fix to the seed does not reach an instance that already seeded
  itself (the `.git` guard is right; a verb that re-seeds a living
  instance from a newer seed does not exist yet).
- `aegis data restore` does not restore objects; after `--force` the
  database role is realigned by hand.
- `aegis secret create <contract>` does not derive the per-namespace
  copy of `regcred-internal`; `secret move` does, with the private key.
- The Jenkinsfile template builds one Containerfile at the repo root;
  a repo with several services keeps its own Jenkinsfile.
- Kyverno reaches only registries the instance's CA signs; a public
  image is refused with an `x509`, not with "no signature".
- The platform at rest reserves ~2.5 CPU; a 4-CPU node fits one build
  at a time, and `aegis check` says so through the CI quota.
- The cloudflare profile has not run on a clean instance: it needs a
  zone, which a rehearsal account does not have. Its first real run is
  the migration of the house machine, with its own safety net.
