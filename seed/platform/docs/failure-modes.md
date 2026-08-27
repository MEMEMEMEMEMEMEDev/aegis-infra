# failure-modes.md — aegis failure classes, signatures and fixes

Source: 14 greenfield validation runs (2026-07) + the engineering
report from the in-VM agent (post-#14). The "run #N / H-N / CR-N /
A-N" comments scattered through the code are the embedded logbook;
THIS file is the index by CLASS — for humans and for AI agents that
need recoverable context without reading 2,400 lines of lib.

House rule: when the same kind of bug shows up 2+ times, the CLASS
is what gets attacked (a helper + a static check with proven teeth),
not the symptom. The four diseases below were born that way.

---

## Disease A — "YAML as a string" (templating by text)

Instances: H4 (#13, `grep -q` guards were matching comments — 4
sites), CR-0/CR-1/CR-2 (#14, replace()/next() injections wrote into
comments or with the wrong indent), H6 (#13, a variant: material
mounted where the consumer does not read it).

Typical signatures (they surface LINKS AWAY from the cause):
- kustomize: `missing Resource metadata` / `accumulating resources`
- helm: `did not find expected key`
- ArgoCD: a permanent ComparisonError on an App that "ought" to be
- an orphaned resource with no error: the entry was never added,
  Secret NotFound

Class fix (in force):
- READING structure: `yaml_lists_file` (only the list ENTRY counts,
  never the comment) — common.sh, check 41.
- WRITING structure: `inject_placeholder` — non-comment, single
  occurrence, the indent of the real line, YAML validated BEFORE
  writing (target left intact if it does not parse) +
  `placeholder_pending` for the re-run — common.sh, check 48,
  harness with the exact shapes of CR-1/CR-2.
- Early detection (Pattern A-2c): build the affected directory
  immediately after the edit (`kubectl kustomize` of the policies
  dir in phase 80; `kubectl apply --dry-run=server` of the CR in
  phase 70 — the KSOPS dir does not build locally). Checks 43/56.
- Double defence: the comments in platform/ do NOT write literal
  placeholders (check 48c).

Decision on ruamel.yaml (option 1 of the report): NO for now. It
would be the definitive fix (assign to the path and serialize), but
it adds a non-stdlib python dependency to the init's host for a
margin that inject_placeholder + validation + checks already cover;
it gets re-evaluated if the class bites again IN SPITE OF the
helper. Recorded as a decision, not as an oversight.

## Disease B — gates that do not isolate the property they verify

Instances: CR-3 (#14, a scope-probe with no limits → the quota
rejected it BEFORE Kyverno did → a red gate for the wrong reason),
CR-4 (#14, the negative case accepted ANY failure → PSS/quota could
give a false green on THE platform's gate).

Rule adopted (for every admission gate):
1. The probe satisfies ALL the namespace's other policies (PSS,
   quota) — the only non-compliant thing is the property under test.
2. The assert goes on the MESSAGE of the deny (it must cite
   `require-aegis-signature`), not on the exit code.
3. On failure, the gate prints the evidence that tells the causes
   apart (gate_diag: events/describe/operationState/console — H7 #13).
Checks 47/50.

## Disease C — eventual consistency treated as synchronous

Instances: the lastBuild race (#9), argo_sync against an
already-Healthy App (#8), CR-2-poll (#14: a restart 2 s after
policy-ready while the deploy still pointed at the PRE-signature
tag).

Rule: after each state transition, the next step polls the
PRECONDITION it needs, never the elapsed time. Examples in force:
argo_sync waits for the TERMINAL phase of the NEW operation
(startedAt); builds are waited for by the NUMBER captured BEFORE the
trigger; phase 80's positive case waits for `@sha256:` in the deploy
BEFORE the restart (check 51).

OPERATIONAL PROPERTY (not a detail): Kyverno does NOT re-mutate
UPDATEs with no image change — a Deployment admitted PRE-policy that
references a tag is left unrestartable (a deterministic deny at the
ReplicaSet) until the next image bump. Any "rollout restart" runbook
in org-personal has to account for this.

## Disease D — dual git state (local clone vs remote)

Instance: CR-6 (#14, a manual fix by the operator on GitHub during a
resume → the init's clone fell behind → risk of overwriting/
colliding).

Fix: `platform_repo_sync` (common.sh) on opening EVERY phase that
mutates the platform repo (25/40/50/70/80): fetch + merge --ff-only;
if it diverged, it dies with the state visible — the init never
decides a merge on its own. Check 52.

---

## Disease E — silence as success (the instrument never looked)

Named in the code long before it was written down here: `aegis check`
calls it "the check passes without having looked at its subject".
The first init on a machine that was not the house one (2026-08-27)
produced the fullest collection of it in a single day:

- the wizard printed "config written" over a `mv` that had FAILED (the
  instance's directory did not exist yet) and the init went on with
  the answers in memory — because `config_wizard || die` suspends
  `set -e` inside the function, and the `mv` had no `|| die` of its
  own;
- the preflight's leftovers check looked at a path that exists on no
  customer's machine and reported "clean";
- `jenkins_build_retry` waited the whole 2700 s for a build that never
  existed: the POST had been refused (a parameterized job needs
  `buildWithParameters`) and every 404 was read as "not started yet";
- the phase-80 gate that "pins the canary to a digest" accepted ANY
  `@sha256:` — the unsigned image already had that shape;
- the round said "could not count the tenant probes" about a
  measured zero (no tenant declares a domain).

Typical signature: a green line, or an infinite wait, with the cause
one step BEFORE it — a write that did not happen, a request that was
refused, a comparison against the wrong thing.

Class fix (in force):
- every write that matters carries its own `|| die` (checks 142,
  060); a trigger is followed by "does the build EXIST" before "did
  it finish" (`_jenkins_build_appears`, check 060);
- a gate compares against THE value, not against a shape
  (`grep -qF "@$DIGEST"`, check 071);
- a measured zero is said as a zero, and "could not evaluate" is
  reserved for the instrument not reaching its subject.

## Disease F — product == instance (the house machine hides it)

Until the day the artifact ran on a machine that was not the one it
was written on, the product's repo and the instance's directory were
the same folder, with leftovers of every earlier run in it. Whatever
the init did not do, the folder already had. The first clean instance
found, in one day, everything that folder had been hiding:

- the instance's `platform/` was seeded in phase 10, and phases 00 and
  05 had been reading it all along (check 141);
- three encrypted secrets that ksops generators listed and NO phase
  wrote — they came from a hand-run `aegis secret create` years of
  runs ago; without them the garage App never rendered (check 145);
- `ci/write-digest.mjs`, which every Jenkinsfile runs, was in the
  canary's repo from earlier builds and in no seed (check 005c);
- `/usr/local/bin/aegis`: two comments said phase 05 installed it;
  nothing did (check 143);
- the preflight assumed the VirtualBox VM it was born on (NIC names,
  the NAT's DNS) and the wizard's defaults named the operator's own
  repositories;
- the build agents' CPU RESERVATIONS were sized for the house
  machine: on a 4-CPU node the platform at rest reserved 2.5 and a
  build asked for 1.6 more — no build could ever schedule, and the
  Pending pods held the CI quota so nothing else could either;
- the canary's Application was declared in two files, and the two
  drifted the first time one was edited (check 146).

Class fix (in force): `lib/paths.sh` is the ONE place that decides
where the product and the instance are; the checks above derive their
lists from the code (generators, Jenkinsfiles, entry points) instead
of enumerating; and the rehearsal on a foreign machine is a recurring
practice, not a one-off (`docs/journeys/foreign-instance.md`).

## Disease G — presence is not identity (re-init over a previous instance)

`aegis destroy --k3s` removes the cluster and the host bridge; it
leaves the instance's `platform/` (the customer's repo, with their
contracts), the store and the conf — on purpose. The init that runs
next reuses them and converges in minutes... and inherits, inside
`platform/`, everything an EARLIER cluster wrote there:

- the CA of a cluster that no longer exists, injected into Kyverno's
  values and blackbox's ConfigMap. Every injection guard asked "is
  the placeholder still there?" — it was not, so the dead CA stayed;
  Kyverno, not trusting the new registry's certificate, fell back to
  plain HTTP against an HTTPS server and refused every image;
- the signature policy already listed in the kustomization — phase
  80 is "the LAST one to turn it on", and the seed is born with it
  off; a repo from a previous cluster is born with it ON, before
  Kyverno has a CA or a credential;
- image digests of a registry that no longer exists: in the bucket
  provisioner's Jobs, in the tenants' overlays, in `services.yaml`.

Typical signature: a green gate over a stale thing; `x509` or
"Client sent an HTTP request to an HTTPS server" in Kyverno's log;
ImagePullBackOff on a digest git swears by; a sync that waits on
hooks forever.

Class fix (in force):
- injected PEMs are COMPARED with the live CA and re-injected when
  they differ, with the consumer restarted (`pem_stale`,
  `reinject_pem`, phases 80/85, check 068);
- phase 35 turns the signature policy OFF when it finds it on, and 80
  turns it on again in order (check 039);
- Garage is synced after the mirror, without hooks; the hooks run on
  the next ordinary sync (phase 80);
- what the init does NOT repair, and the operator does after a
  re-init on a host with tenants: `aegis org apply orgs/*.yaml` (the
  provisioner's Jobs get this registry's digest) and `aegis sync
  garage`; the tenants' own builds re-run through the pipeline.

## Disease H — mention is not use (the text claims what the code does not do)

A comment, a help text or a docstring describing behaviour that no
code implements. Found on the same day: `aegis destroy --help` said
it deleted the GitHub repos (it never had); two entry points explained
their `readlink -f` with "phase 05 installs the symlink" (nothing
did); `aegis secret create`'s docstring said contracts and files were
"told apart by the extension" (the code sent both to the contract
branch); the injection guards' comments promised idempotence they had
for the placeholder only. The checks that exist for the class
(`mention != use` is written into several of them) read the CODE, and
treat a claim in prose as the thing to verify, not as evidence.

## Network / environment transients (E-1)

The dev environment is intermittent BY DESIGN (the operator's mobile
connection) and the VM's DNS gets dirty. Where the tolerance lives:
- `retry_net` on every one-off egress (git, curl, gh).
- `argo_secrets_gate` classifies ComparisonError: a network
  signature (dial tcp / i/o timeout / lookup / EOF / connection re*)
  = wait; broken kustomize = immediately fatal.
- After 60 s of sustained transient the DNS runbook (§1.9 of
  VALIDACION) is printed as a HINT. The remediation (restarting
  CoreDNS) is the operator's decision — the init does not restart
  cluster components on its own.

## Accepted risks (decisions with a cost, not bugs)

- **Single-node / fail-closed**: a hard Kyverno crash freezes
  org-personal. Deliberate (A44, bounded blast radius).
  Pre-Hetzner: 2-3 replicas of the admission controller + a
  PodDisruptionBudget (the values file already notes it).
- **Bash as the orchestrator (~2,400 lines of lib)**: fine as long
  as the primitives (gate/poll/injection/store) are extracted into
  libs with a harness — which is the current state. Rule: do not
  grow without a harness for the new primitive; migrating language
  is NOT urgent.
- **The registry's fixed ClusterIP on the INIT's paths** (curl,
  cosign verify): the cert carries the IP in its SANs and it works;
  the manifests already use the NAME. Since H2 (#13) the host
  resolves the name through /etc/hosts, so unifying init→name is
  possible — DEFERRED deliberately to post-#15 so as not to touch a
  validated path before the hands-off run (recorded in VALIDACION
  §5). A CIDR change today breaks in ~4 places at once: that is the
  accepted cost.
- **tlog/SCT switched off** (rekor.ignoreTlog + ctlog.ignoreSCT +
  --tlog-upload=false): correct for offline signing without Sigstore
  SaaS; it means ZERO transparency of signatures. If aegis aims at
  multi-tenant production: re-evaluate a self-hosted Rekor (trigger:
  the same one as on the rotation list — the first client with an
  SLA).
- **Debt #103**: background:false in the policy (drift detection
  switched off). Trackable in the backlog; the global CA would
  already allow it.

## Design ↔ code traceability (D-1)

Rule adopted after #14: every success criterion of the design has
(a) its assert in code, or (b) an explicit record of "not
implemented + why". The case that gave birth to it: "close issue
#56" — clarified in VALIDACION.md (a task on the session's internal
backlog, closed MANUALLY by the operator; the init closes nothing).

## Run diagnosis for agents (P2.13)

Every gate appends JSON to `init/.init-state/gates.jsonl`
(`{ts, phase, gate, result, duration_s}`) — a past run is diagnosed
with jq, without parsing the ANSI log:

    jq -r 'select(.result=="fail") | "\(.phase) \(.gate) \(.duration_s)s"' \
        init/.init-state/gates.jsonl
