# AGENTS.md — the contract for working on this artifact

This file is for the agent (AI or human) who is going to MODIFY
aegis-v3: add features, fix bugs, take items off the backlog. Read
it end to end before touching anything — almost every rule here was
born from a real incident that cost a run.

If instead you are on the machine where the platform RUNS →
`OPERATE.md`. The vocabulary is law and lives in `glossary.md`. The
historical why of v3 — the working record between the operator and
Claude — is `plan/`, `ENCARGO.md` and `EJECUTADO.md`, and those stay
in Spanish on purpose.

---

## 1. What this is and what state it is in

aegis-v3 is the declarative bootstrap of the aegis platform, split
in two the way v2 never was:

- the **product** (`AEGIS_ROOT`) — this repo: `bin/` (the
  dispatcher), `libexec/` (one file per command), `lib/` (the shared
  helpers, bash and python), `init/` (the orchestrator and its 15
  idempotent phases), `verify/` (the verifier), `seed/` (what
  ships). Read-only for the duration of a run.
- the **instance** (`AEGIS_HOME`) — one machine's living state:
  `platform/` (the GitOps repo the init deploys), `.init-state/`,
  `.state-secrets/`, `aegis.conf`. Mutable.

Where each thing lives is decided in exactly one place —
`lib/paths.sh` and its python twin `lib/aegis/paths.py` — and both
read the same environment variables, so a bash command and a python
one sitting side by side cannot disagree about where the instance
is.

The platform repo is not written by hand: it is instantiated from
`seed/platform/`. The rule is structural — **what does not go in
through `seed/` did not go in.**

State: **VERSION 2 CLOSED (2026-07-24)** — validated end to end
against a real VM: 14/14 phases, 146+ gates green including the
fail-closed ones, an isolated tenant (netpols, RBAC, unprivileged
build, signature + Enforce admission), and recovery tools
(backup/restore/rotate/destroy) exercised. v3 is the rebuild of that
same artifact around the product/instance split and an English
surface; its plan is in `plan/` and what has been executed is
tracked in `EJECUTADO.md`.

The canonical sequence of phases and decisions D1–D11 are in
`platform/docs/architecture/bootstrap.md`. **If that doc and the
init diverge, that is a bug: they get fixed together, in the same
commit.**

## 2. The two worlds: where you are standing

- **The product repo (the operator's desktop)** — THE repo lives
  here: `~/Escritorio/workspace/aegis-v3` (git, private remote).
  This is where you edit, where you run `aegis verify`, where you
  commit. It is the operator's PRIMARY machine: extreme care with
  destructive commands (`rm -rf` is effectively forbidden outside
  scratch).
- **The instance (disposable)** — this is where the init RUNS and
  where all the mutable state lands. It is disposable by design; the
  product repo never is. v3's first real run goes on the VPS lab, in
  the local profile (`platform/docs/protocols/vps-lab.md`, and the
  `aegis vps` command); the house instance comes second.

A wrinkle that used to be here: `aegis preflight` was born on the
VirtualBox VM v2 ran on and assumed that shape everywhere (it pinned
the NAT NIC's DNS to VirtualBox's resolver, with a boot service to
re-apply it). Since 2026-08-27 it MEASURES that shape — the NAT NIC
exists and sits on 10.0.2.0/24 — and touches no DNS anywhere else; the
first run on a VPS is what found it.

The plan (the wave roadmap, the run packages, the decisions and the
dissents) lives in `plan/` inside this repo, together with
`ENCARGO.md` (what was asked for) and `EJECUTADO.md` (what has been
done). All three are in Spanish, and stay that way: they are the
working record, not the product.

## 3. The method (non-negotiable)

Every change follows this cycle, with no skipping:

```
1. ONE item = ONE commit (Conventional Commits).
2. The fix attacks the CLASS, not the symptom (if the same kind of
   bug shows up twice → a canonical helper in lib/).
3. Every fix/feature carries its check in verify/checks/ — one
   check is one file, with exactly one verdict.
4. Every check is validated with its TOOTH, in verify/teeth/: you
   mutate the code (you break what the check protects) and verify
   that the check FAILS. A check that does not bite does not exist.
5. `aegis verify`: ALL PASS before committing.
6. Nothing is "done" until a RUN validates it on a real instance.
   The operator launches the run; you prepare the package (what to
   watch, which gates are new, how to diagnose it if it stalls).
```

On teeth: weak mutations produce false confidence. The correct
mutation is the REAL regression (the bug that motivated the check),
not a cosmetic change. It is documented that well-made teeth caught
bugs in the checks themselves.

On runs: the standing criterion is ONE pass from a clean starting
point, zero manual interventions, exit 0, `gates.jsonl` archived as
evidence. `--from <phase>` is allowed only during iterative
debugging, never as final validation.

## 4. Hard rules (each one has a corpse behind it)

### Secrets

- NEVER print the contents of Secrets: not `kubectl get secret -o
  yaml/json`, not `--decode`, not base64. Shape checks by length
  only (`wc -c` over a file).
- Secrets NEVER in argv (`/proc/PID/cmdline` is public):
  `--from-file`, stdin, `htpasswd -i`, `jq --rawfile`.
- SOPS encrypts AT the repo path (the creation_rule matches by
  path): `mv` first, `sops -e` after, roundtrip ALWAYS
  (`sops -d | head -c1`).
- Cleartext material only in tmpfs (`/dev/shm`), chmod 700, shred on
  exit.
- K8s Secrets via `data:`, byte-preserving; NEVER a `stringData`
  assembled by hand (YAML folding adds 1 byte and breaks HMACs).
- Shared credentials (htpasswd↔regcred, HMAC↔webhook): ONE origin,
  derivation in the SAME process, ONE commit.
- The age key is THE irreducible: never in a backup bundle, never in
  a log, never in the repo. Everything else is recoverable with it.
- The full dozen: `platform/docs/conventions/secrets.md`.

### Verification

- **The binary decides, the doc is a hypothesis.** Versions, flags,
  CRD schemas: verify against what is deployed (`kubectl explain`,
  `--dry-run=server`, real tags from the remote registry), never
  from training memory. This project has 7 documented instances of
  "the doc lied" and at least 2 of "the pin invented from memory did
  not exist".
- Do not claim "it is done" without verifying at the source. Roadmap
  ≠ state.
- The defining test is the one from the real CONSUMER
  (client→real server), not a local read that proxies for it.
- Bring resources byte-identical to the ones that worked live; do
  not reconstruct them from memory.

### The init's code

- stdout is SACRED: all logging to stderr. Any function whose value
  is captured with `$()` cannot log to stdout (it bit twice).
- Never `if (source phase)`, nor conditions that wrap code with
  `set -e` — bash ignores errexit in a condition context (it was
  dead for 15 runs). The pattern is: `set +e; (source); rc=$?;
  set -e`.
- YAML never by text: read structure with `yaml_lists_file`, write
  with `inject_placeholder` (which validates the YAML before
  writing). `grep -q` guards over YAML are forbidden (check 041) —
  they match comments.
- Convergence before measurement: EXISTENCE → STABILITY → MEASURE
  (`wait_for` / `k8s_converged` / `deploy_current_pods_ok`).
  `items[0]` over cascading collections is forbidden (check 072).
- Transient ≠ failure: "it did not converge" waits with a generous
  timeout; "it converged to an error" stops with a diagnosis.
  Network signatures are centralised in `AEGIS_NET_SIGS`.
- Every gate: can fail, isolates the property it verifies (the probe
  satisfies ALL the namespace's other policies), asserts the
  rejection MESSAGE, speaks when it fails (`gate_diag`) and records
  into `gates.jsonl`.
- Revert steps NEVER with `&&` — each step with its exit code
  visible.
- tofu ALWAYS via the wrapper (`platform/tofu/tofu-apply.sh`) —
  bare, the TF_VARs are missing and there are phantom destroys of
  count-gated resources.
- On the host side: python3+pyyaml (yq is NOT installed on the
  operator's machine).

### Git and repos

- The repos the init writes to are DISPOSABLE (topic
  `aegis-v2-disposable`). No marker → ABORT. Never operate against
  the operator's real repos.
- Workflow: feature branch → PR/merge into main. Integration merges
  with `--no-ff`. Never commit straight to main without agreement.
- Never delete or force over something you did not create without
  first looking at what is there.

## 5. Autonomy: when to stop

Classify every action BEFORE executing it:

- **GREEN (flow)**: read, search, edit code + check + tooth, run
  `aegis verify`, commit on your own branch.
- **YELLOW (one brake: show it and wait for an OK)**: merge into
  main, push, design changes that were not discussed, touching paths
  already validated by a run, anything on the instance that mutates
  cluster state.
- **RED (stop and ask)**: everything irreversible (a real destroy,
  rotating irreducibles, deleting external resources — webhooks,
  DNS, repos), everything that touches secrets in the clear, and any
  diagnosis where your hypothesis contradicts the operator's
  evidence (it happened twice; the operator was right both times).

Rule of diagnosis: faced with a symptom that has multiple known
causes (e.g. "webhook 400" has TWO), discriminate with evidence
BEFORE touching anything. Deleting a resource on a wrong hypothesis
cost an entire run.

## 6. How to run the tools

```bash
# The static suite (from the repo root):
aegis verify                    # 118 checks; exit 0 = PASS
aegis verify --with-charts      # + renders the real pinned charts
aegis verify --only 079         # just one check
aegis verify --teeth            # 243 teeth: mutate on purpose and
                                # require the check to turn red
aegis verify --harness          # the functional harnesses

# exit 3 = A BUG IN THE VERIFIER (not in the artifact): a check with
#          no verdict, with two, or not deterministic across passes

# The init (ONLY on the instance, never on the product machine):
aegis init --check                 # dry run
aegis init --profile greenfield    # full run
aegis init --from 50-jenkins       # resume (re-executes the phase)
AEGIS_VALIDATE_FAILCLOSED=1 ...    # enables the disruptive gates

# Out-of-band tools (on the instance):
aegis state backup      # age-encrypted bundle + verified ROUNDTRIP
aegis state restore     # the inverse; --force to overwrite
aegis rotate            # DRY-RUN default; --yes invalidates the store
aegis destroy           # DRY-RUN default; --yes destroys CF + purges

# Maintainer tools (hidden from the main menu, but verified):
aegis dev seed diff     # what the instance has and the seed does not
aegis dev test-types    # acceptance test of the contract types
```

`bin/aegis` is the dispatcher: `aegis <name>` looks for an executable
called `aegis-<name>` in `libexec/` and execs it. Phase 05 installs it
into the PATH as a symlink, which is why every command resolves the
product with the canonical preamble (readlink, then two levels up)
and never from `$0`'s directory.

Diagnosing a historical run without parsing ANSI logs:

```bash
jq -r 'select(.result=="fail") | "\(.phase) \(.gate) \(.duration_s)s"' \
    "$AEGIS_HOME/.init-state/gates.jsonl"
```

## 7. The shape of a typical change (a real example)

Commit `a068a1c` in v2's repo (the fix for the kube-router race) is
the mould:

1. A real bug in a run: gate `trivy-responde` exit 7 with a correct
   netpol and a healthy service.
2. Live diagnosis with evidence (exec-curl OK, a fresh pod fails
   5/5 → the CNI is slow to program the ipset).
3. A class fix: retry INSIDE the pod (not outside — a new pod per
   attempt re-enters the race).
4. A static check: the phase 80 probe must retry intra-pod (check
   079, with awk over the gate's real block).
5. A tooth: `sed 's/for i in 1 2 3/NOTHING_AT_ALL/'` → the check
   fails → the tooth bites.
6. One commit, a message with the why, a reference to the run.

## 8. Recommended reading order to get started

1. This file (you are already here).
2. `glossary.md` — which English word stands for which idea. It is
   binding, and `aegis verify` enforces it (check 111).
3. `cli/design.md` — the dispatcher, the derived help, and the
   old→new command map of §4.
4. `platform/docs/architecture/bootstrap.md` — the sequence and its
   whys.
5. `platform/docs/conventions/secrets.md` — the hard rules.
6. `platform/docs/failure-modes.md` — the failure classes and their
   signatures.
7. `journeys/foreign-instance.md` — the rehearsal on a machine that
   is not the house one: what travels, what is answered, what it
   found. Read it before touching a phase: most of what the static
   checks cannot see lives there.
8. The code: `libexec/aegis-init` → `lib/common.sh` → the phase you
   are going to touch → the checks that cover it in
   `verify/checks/` (search for the phase number or the gate name).

---

*Last updated: 2026-07-24, at the close of VERSION 2. Translated to
English and brought to the v3 tree on 2026-08-24.*
