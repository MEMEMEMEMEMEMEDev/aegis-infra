# bootstrap.md — THE canonical source of the aegis v2 sequence

It replaces the v1 overview §8-9 (which went stale against
ADR-0011/0015/0003 — drift that ADR-0011:123 left as a TODO). If
this document and the init diverge, IT IS A BUG: they get fixed
together.

## Identity

aegis-init ≡ task #56 ≡ DR Level 3 ≡ Hetzner bootstrap. ONE
artifact, profiles: greenfield (full v1) | hetzner (deltas) |
re-bootstrap (NOT implemented — known limit, see §Known limits).

## The sequence (15 phases, init/phases/)

```
00 preflight      GUIDED config (wizard: it asks + validates +
                  writes; never "go fill in this file") + limits
                  + verified preconditions
05 host           installs a PINNED Linux userland; VERIFIES the
                  Windows side (actionable checklist, it does not
                  automate)
10 age-ceremony   generates the root of trust; 3 backups
                  VALIDATED by roundtrip; .envrc/direnv;
                  .sops.yaml
12 workrepos      CREATES and SEEDS the work repos it owns
                  (aegis-platform / aegis-canary by default) via
                  gh, idempotent through a topic marker; B4
                  settings through gh api; known_hosts from the
                  T1 pins
15 third-parties  AUTOMATIC (D11): ONE ephemeral CF master
                  credential → scoped tokens minted through the
                  API; deploy keys registered by gh; 2 webhooks
                  through gh api; CI credential = gh token (the
                  GitHub App was REPLACED — creating one without
                  a browser does not exist); encrypts 8 Secrets
                  + tokens
20 k3s            ansible: pinned kernel+k3s; [hetzner: Cilium
                  BEFORE any NetPol]; storageclass; VERIFIED
                  kubeconfig (the pothole of the foreign cluster)
25 edge-tofu      tofu for Cloudflare ONLY (D10): tunnel +
                  CNAMEs; TUNNEL_TOKEN → KSOPS Secret with no
                  screen; commit+push of the encrypted files
30 argocd         THE one imperative installation: bootstrap
                  Secrets through KUBECTL (D2: age never in a
                  state) + helm install (same values as the App)
35 gitops         root + syncs IN ORDER: argocd-secrets → argocd
                  (ADR-0015) → cert-manager → PKI → issuers →
                  traefik → cloudflared; end-to-end edge gate
40 registry-pki   htpasswd + 4 ATOMIC regcreds (one process);
                  registry with TLS FROM DAY ONE; CA onto the
                  host by an Ansible role (per node)
50 jenkins        random admin; secrets→chart (order); JOBS-AS-
                  CODE from birth (disposable PVC); the
                  ci-images job builds the tooling (no longer
                  by hand)
60 webhook        completes the App's URL; e2e gate: a REAL push
                  → a REAL build
70 deploy-auto    pattern-A tenant; canary with a real pull (THE
                  gate of the registry→kubelet path); ANTI-LOOP
                  PROVEN BEFORE the write-back; IU dry-run →
                  gate → flip
80 supply-chain   trivy server; cosign CEREMONY; FIRST SIGNED
                  IMAGE; kyverno; kyverno-policies LAST (D5 —
                  Enforce with no prior signature rejects
                  itself); final gate: positive mutated to a
                  digest + negative rejected + scope respected
```

Sync order = mechanism (there are no sync-waves): root is MANUAL
(ADR-0012) and the init decides the when of each App. General
rule: every *-secrets App BEFORE its consumer.

## v2 vs v1 decisions (each one with its why)

- **D6 — tofu without K8s**: v1 installed
  cert-manager/traefik/argocd through tofu-helm (ADR-0011) and
  then paid the whole of Half B to hand them over to GitOps
  (removed blocks, adoption). v2 does not create that debt: helm
  install ONLY for argocd, GitOps for everything else. The
  tfstate is left without a SINGLE cluster secret. A deliberate
  departure from ADR-0011 — the problem ADR-0011 solved
  (circularity) only existed for argocd itself.
- **D2/D3 — secrets**: age/deploy keys through kubectl, never a
  provider; human pauses grouped together (phase 15);
  structurally atomic derivations (lib/secrets.sh); ceremonies
  with a roundtrip for the irreplaceable ones. Model:
  random+Bitwarden as the main path, manual double-typing as the
  exception (verdicts 20.2/20.3 of the report).
- **D5 — H-7 encoded**: kyverno-policies last, after the first
  signature.
- **D9 — jobs-as-code from birth**: Jenkins's PVC is disposable;
  the jobs live in JCasC job-dsl (syntax verified in v1 3.B.3).
- **B4 fixed at the root**: delete_branch_on_merge=false in the
  env AND in the module's default.
- **Registry TLS from day one** (2026-07-04:7).
- **Ansible role registry-host-trust**: v1's manual sudo block
  (2026-07-02:132) is a per-node playbook.
- **D10 — GitHub outside tofu; the init's own work repos**: the
  repos the init uses are ITS OWN and DISPOSABLE (created and
  seeded by phase 12 with the `aegis-v2-disposable` marker) —
  never v1's real repos (the init WRITES to them: commits, tags,
  settings, webhooks, the IU's write-back). With the repos
  pre-created by gh, the github-repos tofu env contributed only
  state + a PAT + an import problem: settings and webhook go
  through idempotent gh api (the secret through --input, never
  argv), the PAT was REMOVED from the flow (the credential is
  the operator's gh session) and tofu is left Cloudflare-only
  (1 TF_VAR). It also fixes the sequencing bug: phase 15's
  deploy keys are registered against repos that by then already
  exist.
- **Guided config (the operator's mission)**: an interactive
  wizard in phase 00 — explanation + inferred default +
  per-field validation, and the init WRITES the .conf. A
  pre-made .conf is respected (re-runs/automation). Same
  principle as the secrets: the init asks and does; the operator
  decides and confirms.
- **D11 — total automation (redesign after run #2)**: manual
  friction is NOT security. ZERO browser, ZERO files moved by
  hand, ZERO tokens created in panels, agnostic prompts (the
  init assumes no particular secret manager). Pieces:
  (a) the GitHub App REPLACED by the gh session's token as the
  scan credential — creating it headless DOES NOT EXIST
  (manifest flow = a web redirect), and neither does minting
  PATs through the API; trade-off and upgrade path in
  docs/protocols/github-credential.md. (b) Cloudflare: one
  ephemeral MASTER credential (it lives only in tmpfs during
  phase 15) mints the 2 scoped tokens through the API
  (permission groups matched BY NAME against the live list) and
  is destroyed with shred. (c) Deploy keys registered with
  `gh repo deploy-key add`. (d) An encrypted state STORE
  (init/.state-secrets/, age): every generated secret is
  persisted and the --from flags REUSE instead of regenerating —
  the cycle of orphaned credentials dies. (e) The ONLY
  irreducible human act: backing up the age key (everything else
  is recovered with it); the cosign ceremony is gone. (f) The
  orchestrator RE-DERIVES the environment (SOPS_AGE_KEY_FILE,
  AGE_PUBLIC) before each phase — no phase depends on another
  one's export (the family of state bugs from run #2).

## Known limits (v1 of the init)

0. The work repos (aegis-platform / aegis-canary by default) belong
   to the init and the platform: they write to them freely. Promoting the result to "production" is a later
   decision of the operator's (rename/clean up/re-bootstrap),
   outside the scope of this init.
1. Total loss of GitHub: no path (it starts with a clone). H4.
2. Re-bootstrap with an import of live CF/GitHub resources: no
   procedure (greenfield RECREATES). H5.
3. Windows side: the checklist is verified, not automated.
4. Recreating the tunnel can leave DNS residue from the previous
   one (behaviour with no source — DOCUMENT the result on the
   first validation).
5. The fail-closed gates with force-kill (a hard Kyverno crash)
   belong to the VALIDATION, not to every bootstrap (they are
   disruptive).
6. Total time: "~1 h" is NOT promised until it has been measured
   (the init itself emits the figure — observability/design.md
   §1).

## Validation (≡ closing task #56)

Run the COMPLETE greenfield profile in a virgin environment —
building and validating are ONE milestone. Environment candidates
(an open decision of the operator's): a clean imported WSL2
instance (faithful to the local host) / a Hetzner VM (faithful to
the hetzner profile). Each profile is validated on its own
ground.
