# Journeys — the design of the app protocols, WITH NO CODE YET

Scope: how a user creates an app in aegis and takes it to prod without
it being terrible, how it grows afterwards, and how the platform's
catalogue grows with it. Same criterion as observability/design.md: the
decisions are taken here; the bash arrives later and finds them already
taken. Nothing in this document exists yet except what is marked
[TODAY].

## 0. Principles (the ones that order everything else)

1. **The contract is the only truth.** `orgs/<n>.yaml` is the input
   EVERYTHING is derived from. A template generates contracts; a journey
   writes them by hand; neither creates a second source of truth.
2. **Files and world, separated with a pause in between.** Generating is
   harmless and reviewable (git diff); executing against the world
   (GitHub) is deliberate and comes afterwards. It is tofu's plan/apply,
   applied to onboarding. The border lives at the SUBCOMMAND level (see
   §3).
3. **The template evaporates.** It instantiates a contract plus initial
   code and disappears: from that moment on the user is one more
   artisan. Zero apps "tied to their template" — we are not a framework.
4. **Converge, do not execute.** Every command re-run with the work
   already done ends in "nothing to do". Create-if-missing, never
   recreate-just-in-case.
5. **Firm rails in the centre, freedom at the edges.** The extension
   points (substrates, templates, checks) are documented with a
   checklist so that each instance can customise ITS aegis through the
   marked doors. What does not get customised: the border in §0.2, the
   signature, the contract as truth.

## 1. The three journeys

| journey | who it is | what it does |
|---|---|---|
| artisan | wants pure IaC and control | writes `orgs/<n>.yaml` by hand; runs `aegis org apply` + `aegis secret create` [TODAY] + `aegis app apply` (new, closes the GitHub steps) |
| template | wants to start from something that already works | `aegis app new <org> --template <t>` → contract + skeletons; reviews; `aegis app apply` |
| silent | advanced, wants neither demo nor noise | `DEMO=ninguna` in `aegis.conf` → a bare platform; the other two journeys stay available, unused |

The same machinery, three doors. No journey locks anyone in: the
template user edits their contract by hand the next day and nobody
notices.

New config: `DEMO=portafolio|ninguna` (default `portafolio`) in
`aegis.conf` — field T1, asked by the wizard.

## 2. `aegis org` gains two derivations (going from 8 to 10)

Both follow the existing pattern: total re-derivation of their own
block, idempotent, with precedent for touching files outside
`organizations/` (the edge in `main.tf`, the keys in argocd-secrets).

**2a. The Jenkins multibranch job.** Today: 20 lines of job-dsl copied by
hand into `k8s/base/platform/jenkins/values.yaml` for each app —
derivable from the contract's `repo:` and not derived (hole #2 of the
onboarding map). Design: a delimited block in that values.yaml, owned by
the generator:

    # --- DERIVED by aegis-org (tenant jobs): do not edit by hand ---
    ...one job per service with a repo, from every contract...
    # --- END DERIVED ---

Outside the block, what was written by hand survives (the platform jobs
such as mirror-images). Migration debt noted: the 5 current jobs are by
hand and `org-canary` has no contract — they move into the block when
their org has a contract, not before.

**2b. The instantiated Jenkinsfile.** The template has 1 CHANGEME in 452
lines: it is instantiated from the contract (`IMAGE = '<org>-<svc>'`)
into the skeleton's staging area (see §3). The template stops being
copied by hand; it remains ONE, versioned in docs/protocols/templates/.

## 3. `aegis app` — the new command, and where its border lives

Two subcommands, and the house rule engraved in the header: **`new`
writes files and NEVER touches the world; `apply` touches the world and
NEVER writes into the repos.** (a mirror of aegis-org's "IT DOES NOT
TALK TO THE CLUSTER"; a candidate for a check in `aegis verify`.)

**`aegis app new <org> --template <t>`** (files only):
1. instantiates `orgs/<org>.yaml` from the template (aborts if it
   already exists: a live contract does not get trampled — it gets
   edited by hand)
2. instantiates the code skeletons into a LOCAL staging area:
   `.aegis-app/<org>/<svc>/` (gitignored: the destination is ANOTHER
   repo, versioning it here would be the platform/ mistake all over
   again)
3. runs `aegis org apply` (which already includes §2a and §2b)
4. runs `aegis secret create`
5. prints the pending diff and the next step

Re-running it converges; without `--template` it serves the artisan who
already wrote their contract (it skips 1-2).

**`aegis app apply <org>`** (world only, reads what was generated):

| step | idempotence guard |
|---|---|
| a GitHub repo per service with a `repo:` | exists → does not create. `gh repo create` only if missing |
| push of the skeleton from staging | ONLY if the repo is EMPTY (0 commits). A repo with history is never trampled — the artisan brings their own and this step is a no-op |
| deploy key | compares the fingerprint against the generated public key; registers only if missing (`gh repo deploy-key add` — the "irreducible" step of `aegis secret`, reduced) |
| webhook | delegates to `aegis webhook apply` [TODAY, already idempotent] |
| verdict | three outcomes per step: done / already / COULD NOT — the third is a warning, not a green light (Disease E) |

Two things stay human on purpose: the commit+push of the platform repo
(an act of governance) and the `tofu apply` of the edge (the operator's,
by design, #46). `aegis app apply` finishes by saying them, not by doing
them.

## 4. Templates

Structure: `seed/templates/<name>/`
- `contract.yaml.tpl` — the contract with `__ORG__` and `__DOMINIO__`
- `repos/<svc>/…` — complete initial code per service: source,
  `Containerfile`, `k8s/base/` + overlay (the Jenkinsfile does NOT go
  here: §2b instantiates it from the canonical template)
- `README.md` — what it raises, what decisions it made, and that it
  evaporates

A small catalogue ON PURPOSE — each template is living code that rots,
and the defence is to keep few of them and watch them:
- `base` — a bare http service. The minimum that compiles and deploys.
- `portafolio` — the init's demo (see §5).
- `ecommerce` — the flagship. It gets built first AS A REAL APP on the
  live instance using these protocols (that is its test bench); it is
  promoted to a template when it matures. Not before.

## 5. The portfolio demo

A stack chosen for a minimal rot budget:
- front `estatico`: plain HTML/CSS/JS. Zero build, zero node_modules —
  it cannot rot because there is no tree to rot.
- api `http`: Express. Two real dependencies (express, pg).
- `postgres`: a platform substrate [TODAY].
- `bucket`: Garage [TODAY on the instance; in the seed: PENDING #42].
  A clarification of names: Garage is the SERVER (self-hosted, in the
  cluster); "S3" is the PROTOCOL it speaks — the de facto standard of
  object storage, invented by Amazon but spoken by everyone. Zero AWS
  involved: the data never leaves the cluster. WATCH OUT: the backend's
  S3 client is where the one fat dependency sneaks in — the official
  SDK weighs hundreds of packages; evaluate signing SigV4 with a
  minimal library (underneath it is ordinary HTTP with a signature).
- a pipeline COMMENTED line by line: the demo also teaches.

**The demo as a rot canary**: a pinned image does not age safely — it
accumulates CVEs while sitting there, and the scan only runs at build
time: an app nobody pushes to IS NEVER RE-SCANNED. The demo's job carries
a cron (the edge-chequeo pattern) so that it builds periodically with no
changes: ageing turns into a visible red build instead of silence. Free
work that it does by existing.

Init: a new phase `90-demo.sh` — if `DEMO=ninguna`, a no-op with a log
line; otherwise it runs `aegis app new portafolio --template portafolio`
+ `aegis app apply portafolio` + a commit (the init DOES commit: it is
bootstrap, not governance). The demo exercises the complete template
journey on every bootstrap. To take it down afterwards: `aegis org
delete` [TODAY].

## 6. Protocol: growing the substrate catalogue

For redis, a queue, or whatever the future asks for. Half of it already
exists [TODAY]: mirror-images fetches+scans+signs third parties ("redis,
postgres, whatever", says its own Jenkinsfile). The complete checklist:

1. a line in `mirror-images/images.txt` (origin BY DIGEST) + run the job
   → mirrored and signed
2. an entry in `services.yaml`: the internal registry's image by digest,
   resources, the shape of the credential. The decision is taken ONCE,
   for every org
3. a derivation in `aegis org`: `tipo: <substrate>` in a contract → its
   derived workload (the postgres pattern [TODAY])
4. a category in `aegis secret` for its credential
5. if a GUARANTEE changes (not a capability): a check in `aegis verify`
   (the rule from PENDIENTE.md §5)

A deliberately deferred decision: redis vs rabbit vs nothing. The
e-commerce will ask for it with evidence; with this checklist, adding a
substrate costs an afternoon, not an architecture. A bet on the record:
redis first (sessions/cart); a queue only when there is real async work,
and that day the fight is rabbit vs redis-streams vs a table in
postgres.

## 7. Protocol: app dependencies (the red pipeline with an exit)

[TODAY] the scan blocks CRITICAL/HIGH — that is the gate doing its job,
not a failure. What is missing is the dev's way out:

1. first: bump the dependency's version (the normal fix)
2. with no fix available: a DECLARED exception — a `trivyignore` in the
   app's repo (the mirror-images/trivyignore.yaml pattern [TODAY]) with
   the CVE, a justification and a mandatory **expiry date**
3. an expired exception = a red build again. Without an expiry it is
   invisible debt; with one it is scheduled debt
4. the scan stage reads the repo's trivyignore and lists in the log
   EVERY active exception and its remaining days (visible, not buried)

## 8. Out of scope for this version (decided, not forgotten)

- The AI key ceremony (6 manual steps): a problem with its own shape,
  and the e-commerce does not need it. AI stays pending-and-open.
- Monorepo: v1 is repo-per-service (it fits the multibranch [TODAY]). A
  monorepo requires path filtering in Jenkins — to be evaluated if a
  real app asks for it.
- Migrating the 5 hand-written jobs and the orgs with no contract
  (canary, inherited ecommerce): noted debt, not a blocker.
- Access by contract (private tenant hostnames): today Access belongs to
  the platform; if an org asks for a private panel, it gets designed
  separately.

## 9. Build order (each step usable on its own)

1. §2a+§2b — `aegis org` derives jobs and the Jenkinsfile (kills the most
   painful holes with no new command)
2. §3 `aegis app apply` — closes repo/key/webhook for existing contracts
   (the artisan already wins)
3. §3 `aegis app new` + §4 the `base` template
4. e-commerce ON THE INSTANCE using everything above — every friction is
   a bug in the protocol; on maturing, it is promoted to a template
5. §5 the portfolio template + phase 90-demo + `DEMO=` in the conf
6. everything goes back into the seed (`aegis dev seed pull` / init) —
   a structural rule: what does not come in through the seed did not
   come in

The global acceptance bar: the friend test — an external dev, with a
clone and a contract, reaching a public URL without the operator in the
room.
