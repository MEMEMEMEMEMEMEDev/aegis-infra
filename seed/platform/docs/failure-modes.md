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
