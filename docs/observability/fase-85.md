# Phase 85 — observability (the fine design; B2/B3/B4 implement THIS)

Contract: `init/phases/85-observability.sh`, after 80-supply-chain.
WHY 85: by the time it runs, EVERYTHING it is going to observe
already exists (the registry with TLS, Jenkins with builds, Kyverno
in Enforce, the tunnel alive) — an observability phase placed before
its observed subjects would only have trivial gates, and a gate that
cannot fail measures nothing. The same skeleton as every phase:
`set -euo pipefail`, `source aegis-init.conf`, `platform_repo_sync`
first (the phase MUTATES the platform repo), gates with
`gate`/`gate_diag`, idempotent for `--only 85` over a live instance.

## 1. Layout in the seed

```
seed/platform/k8s/base/observability/
  namespace.yaml            # ns `observability`, EXPLICIT and FIRST
                            # (run #7 bug A: CreateNamespace is not
                            # reliable in kustomize apps — the
                            # registry-system pattern, matched to the
                            # one that works)
  kustomization.yaml        # namespace + raw manifests + ksops generator
  secret-generator.yaml     # A7 EXPLICIT LIST: grafana-admin.enc.yaml,
                            # ntfy-bridge-token.enc.yaml (phase 85
                            # encrypts them)
  ntfy.yaml                 # Deployment+Service+PVC 1Gi+ConfigMap (raw)
  alertmanager.yaml         # Deployment+Service+ConfigMap (raw)
  ntfy-bridge.yaml          # Deployment+Service of ntfy-alertmanager (raw)
  blackbox.yaml             # Deployment+Service+ConfigMap of modules (raw)
  configmap-aegis-ca.yaml   # the CA's PEM for blackbox (placeholder
                            # __OBS_CA_PEM__, GENERATED class, owner:
                            # phase 85)
  trivy-db-age.yaml         # CronJob — namespace trivy-system EXPLICIT
  rules/                    # ConfigMaps of vmalert rules (deadman,
                            # b11, kyverno, trivy-db, cloudflared)
  dashboards/               # ConfigMaps with the grafana_dashboard
                            # label (sidecar) — the 4 from design.md §4.4
  vmsingle/values.yaml      # -retentionPeriod=__OBS_RETENCION_METRICAS__
  vmagent/values.yaml       # scrape configs ENUMERATED (in the A7
                            # spirit: a new target is a new entry, not
                            # magic)
  vmalert/values.yaml       # notifier → alertmanager
  vlogs/values.yaml         # -retentionPeriod=__OBS_RETENCION_LOGS__
  vlogs-events/values.yaml # -retentionPeriod=1y (fixed in both profiles)
  vector/values.yaml        # kubernetes_logs → vlogs; route AEGIS_EVENT
                            # → vlogs-events (jsonline)
  grafana/values.yaml       # persistence OFF (design.md §4.1: with no
                            # PVC there is nowhere for click-state to
                            # accumulate), provisioned datasources,
                            # sidecar ON,
                            # admin.existingSecret=grafana-admin
```

WHY raw manifests and not charts for ntfy/alertmanager/bridge/
blackbox: each one is ONE container with ONE ConfigMap — a chart
would add one more repo to sourceRepos and a values layer per piece
in order to save ~40 lines of readable YAML. The precedent is
registry.yaml: raw, dense and auditable at a glance. Charts are
reserved for what really amortises them (the VM family, Vector,
Grafana).

Applications: `k8s/argocd-apps/observability.yaml` (multi-doc,
core.yaml conventions: ServerSideApply, selfHeal, prune OMITTED,
aegis.dev/* labels, placeholders __GH_OWNER__/…):

| App | source | destination |
|---|---|---|
| observability-base | path k8s/base/observability (kustomize) | observability (+ trivy-system: the CronJob carries an explicit ns; the aegis-platform project allows '*') |
| vmsingle | chart victoria-metrics-single + $values | observability |
| vmagent | chart victoria-metrics-agent + $values | observability |
| vmalert | chart victoria-metrics-alert + $values | observability |
| vlogs | chart victoria-logs-single + $values | observability |
| vlogs-events | chart victoria-logs-single + $values (a separate release) | observability |
| vector | chart vector + $values | observability |
| grafana | chart grafana + $values | observability |

Charts and repos (versions: VERIFY when implementing B2 — the house
pins exactly or marks VERIFY; the precedent is
`cilium_chart_version: "VERIFICAR-ANTES-DE-HETZNER"` in group_vars):

| piece | Helm repo | chart | targetRevision |
|---|---|---|---|
| vmsingle | https://victoriametrics.github.io/helm-charts | victoria-metrics-single | VERIFY |
| vmagent | same | victoria-metrics-agent | VERIFY |
| vmalert | same | victoria-metrics-alert | VERIFY |
| vlogs ×2 | same | victoria-logs-single | VERIFY |
| vector | https://helm.vector.dev | vector | VERIFY |
| grafana | https://grafana.github.io/helm-charts | grafana | VERIFY |

Images for the raw manifests: binwiederhier/ntfy,
quay.io/prometheus/alertmanager, quay.io/prometheus/blackbox-exporter,
ntfy-alertmanager (VERIFY the bridge's registry/image — the xenrox
project), curlimages/curl or alpine/curl for the CronJob. All with an
exact tag, never latest (in the A42 spirit).

NEW sourceRepos in the aegis-platform AppProject
(k8s/bootstrap/appprojects.yaml, enumerated like the existing ones —
NOT '*'): the 3 Helm repos above. They must match observability.yaml's
repoURL exactly (a rule written in appprojects.yaml itself).

## 2. Decisions per piece (the whys that do not fit in the table)

- vmsingle: no replica, PVC 5Gi. The retention of §2 fits easily on a
  single node; scaling to a cluster is the FUTURE hetzner profile's
  problem, not today's.
- vmagent and not scrape-straight-from-vmsingle: vmsingle can scrape
  on its own, but vmagent gives relabeling and an on-disk buffer for
  outages — the dev network goes down BY DESIGN and losing the buffer
  would mean losing exactly the samples from the incident.
- Two VictoriaLogs: design.md §4.1 (retention is global per instance;
  per-stream filters = enterprise, VERIFY).
- trivy-db-age: a CronJob in trivy-system (the DB's PVC is RWO and
  lives there) that reads the DB's metadata and pushes
  `aegis_trivy_db_updated_timestamp_seconds` to
  vmsingle:/api/v1/import/prometheus. RWO CORNER CASE: on a single
  node the second RWO mount only co-locates; on multi-node hetzner
  the CronJob needs affinity to the trivy-server's node — note it in
  the manifest, resolve it when hetzner is switched on (VERIFY).
- blackbox validates the chain AGAINST THE CA (configmap-aegis-ca): a
  probe with insecure_skip_verify would give the same expiry, but it
  would let a WRONG cert through in green — exactly the `-k` that
  P2.4 banished from phase 40. The `registry_tls` module accepts 401
  as success (the registry's auth comes after the handshake; the 401
  IS the proof that TLS and auth are alive — the same criterion as
  the registry-tls-real gate).
- Alertmanager with an emptyDir for silences: a silence is ephemeral
  operational state; losing it on a restart re-alerts, which is the
  SAFE failure. A PVC for silences would be click-state in disguise.

## 3. Secrets (A7, the same path as all the others)

Phase 85 generates with `gen_or_restore` (a re-run = the same value,
bug 6) and encrypts with `make_enc_secret`:

- `grafana_admin_pass` → grafana-admin.enc.yaml (ns observability).
  Grafana sits behind Access BUT keeps its own login: Access is the
  door, not the only lock (defence in depth — the same reason argocd
  was not left anonymous after #76).
- `ntfy_bridge_token` → ntfy-bridge-token.enc.yaml: the token the
  bridge PUBLISHES to ntfy with.
- `ntfy_operador_pass`: the phone app's credential. It does NOT go
  into a K8s Secret (nobody in the cluster consumes it — the same
  reasoning as access_st_id in phase 25): it lives in the store and
  is shown to the operator ONCE via human_step so it can be loaded
  into the app.

The secret-generator entries go IN THE SAME COMMIT as the .enc.yaml
files (a temporal rule, run #4), as a REAL list entry
(yaml_lists_file — H4). All 3 new credentials with a declared
rotation recipe (check 089 demands the complete inventory).

The users/ACL INSIDE ntfy (deny-all by default; the operator reads,
the bridge writes to the `aegis-alertas` topic): VERIFY whether the
pinned version supports declarative provisioning by config
(`auth-users`); if it does, it goes into the ConfigMap with the
hashes; if not, phase 85 creates them via `kubectl exec ntfy user
add` with an idempotence guard — imperative but equivalent to the
registry's htpasswd: auth state on a PVC, generated by the init,
recoverable from the store.

## 4. The profile crosses over into the manifests (the hole, closed)

The decision and its why: design.md §4.3 (concrete values per
placeholder, not a profile name that would demand new templating
machinery). The mechanics:

1. A derivation table in `lib/common.sh` (next to
   render_platform_placeholders, its only consumer):

   | placeholder | greenfield | hetzner | consumer |
   |---|---|---|---|
   | __AEGIS_PROFILE__ | greenfield | hetzner | external_labels of vmsingle/vmagent (the datum's identity) |
   | __OBS_RETENCION_METRICAS__ | 30d | 90d | vmsingle -retentionPeriod |
   | __OBS_RETENCION_LOGS__ | 7d | 30d | vlogs -retentionPeriod |
   | __OBS_CF_CAIDO_FOR__ | 30m | 5m | the cloudflared rule (`for:`) |
   | __OBS_DEADMAN_REPEAT__ | 24h | 6h | the deadman's route in Alertmanager (repeat_interval) |

   The events retention (1y) is NOT a placeholder: it does not vary
   by profile — a constant value dressed up as a variable is a lie
   about flexibility.

2. `_CONFIG_PLACEHOLDERS` gains the 5 names and the sed gains 5
   lines; the existing final verification («no config-class
   placeholder survives») covers them FOR FREE — a half-rendered
   values file dies at the render, not as an unreadable vmsingle
   flag two gates later.

3. Where it runs: the canonical render of phase 10 (a virgin start:
   the seed is copied and rendered whole) AND phase 85 itself after
   bringing files in from the seed (a live instance: the new files
   arrive with live placeholders — §6 step 2). $PROFILE is available
   at both points (a global export of the init).

Corner cases: (a) changing --profile on a re-run does NOT re-render
(the placeholder is already dead) — the profile is identity at birth;
changing it means editing the values in git, documented in the
table's header. (b) dev's deadman at 24h: the laptop's night-time
absence is NOT a signal (dev is intermittent by design); at 6h the
operator would learn to ignore the gap — and an ignored signal is
Disease E by the long road.

## 5. The edge: grafana and ntfy

- The seed's `edge.yaml` adds `grafana` and `ntfy` to `plataforma:`
  — the list `aegis org edge` DERIVES public_hostnames from (nobody
  edits main.tf by hand; the lesson of ai.__ROOT_DOMAIN__).
- Access for Grafana: a NEW file
  `tofu/modules/cloudflare-access/grafana.tf` with the
  `grafana.${var.root_domain}` application reusing the existing
  policies (operator + automation). WHY a new file and not editing
  main.tf: HCL merges every .tf in the directory — a new file is
  COPIED verbatim from the seed into a live instance with no merge
  surgery (§6 step 2), and check 090 discovers it by itself (the
  list of protected hostnames is derived from the module's `domain`
  values… VERIFY that the check sweeps *.tf and not just main.tf; if
  not, it is ONE line of the check).
- ntfy WITHOUT Access — the phone app cannot present a service token
  nor get through Access's login. The lock is ntfy's OWN auth
  (deny-all + ACL, §3). And because it is the first public platform
  route with no Access in front, its IngressRoute carries the three
  middlewares (headers/rate/body) of check 091 — copied from the
  generator the way the canary does. NOTE: check 091 today only
  sweeps platform/k8s/organizations/; extending it to observability
  is part of B4 (otherwise the copy without a comparator falls out
  of sync — exactly what the check exists to prevent).
- The IngressRoutes for grafana and ntfy: in observability-base (the
  argocd pattern: the exposure lives next to the exposed). Grafana's
  without tenant middlewares (it goes behind Access, like
  argocd/jenkins today).

## 6. The phase's order of execution (and its whys)

1. `platform_repo_sync` (CR-6: the clone may be behind).
2. BRING FROM THE SEED whatever the instance does not have — the
   rule from RUTA.md («it comes in through seed/+init/ or it did not
   come in») applied to the live-instance case, where phase 10 does
   NOT re-seed (platform/ with a .git is the truth):
   - copy if missing (NEW files, verbatim):
     the whole of `k8s/base/observability/`,
     `k8s/argocd-apps/observability.yaml`,
     `tofu/modules/cloudflare-access/grafana.tf`;
   - guarded entries in EXISTING files (a structural guard, never a
     grep for a mention — H4): sourceRepos ×3 in appprojects.yaml,
     `grafana`/`ntfy` in edge.yaml, and the hooks of §7;
   - on a virgin start all of this is a no-op: the seed already
     carries it.
3. `render_platform_placeholders` (idempotent; it renders the
   __OBS_*__ of the freshly copied files — §4.3).
4. Secrets (§3) + the generator's entries; commit
   (`git_commit_if_changes`) + `git_push_verified` — ArgoCD reads
   from the remote, not from disk.
5. `kubectl apply -f k8s/bootstrap/appprojects.yaml` — the
   AppProjects are bootstrap infrastructure (class C1, applied by
   kubectl as in phase 35); without the new sourceRepos, a chart's
   first sync would die with "not permitted".
6. The edge: `aegis org edge` (derives public_hostnames) +
   `tofu-apply.sh -chdir=envs/cloudflare-tunnel apply` (creates the
   CNAMEs, the tunnel's ingress and grafana's Access App). A gate on
   the result, not on the intention (§8).
7. Hooks of ≤3 lines (§7) + commit/push.
8. `argo_sync root 300` — root is ALWAYS MANUAL (ADR-0012): the new
   Applications are born here and not before.
9. `argo_sync observability-base` first (namespace + secrets + raw
   manifests: with no ns there is nowhere, with no grafana Secret it
   does not start) — with `argo_secrets_gate observability-base
   <timeout> <sha>` (F-B: Synced to the JUST-pushed revision, not to
   an old one), then the stores (`vmsingle`, `vlogs`,
   `vlogs-events`), then the collectors (`vmagent`, `vector`), then
   `vmalert`, and `grafana` last — producers before consumers, the
   same order-as-mechanism as D5. The canonical `argo_sync` of
   common.sh, never a local one.
10. Re-sync of the hooked-up observed components:
    `cloudflare-tunnel`, `jenkins`, `registry` (+ the netpols touched
    travel in their own apps). The jenkins one RESTARTS the
    controller (a new plugin) — that is the one-time price; phase
    50's Jenkins gate is not re-run, but `wait_rollout
    jenkins-system` is (convergence before measurement, family
    number 1).
11. Ingestion of the history: `curl -T $AEGIS_STATE_DIR/gates.jsonl`
    to vlogs-events' jsonline endpoint (with _stream
    source=aegis-init). Best-effort NO: here the endpoint MUST
    exist — if it fails, the phase fails (unlike hooks.md's future
    per-gate push, which is best-effort because it runs before the
    destination exists).
12. Final gates (§8).

## 7. The hooks this phase applies (hooks.md, executed)

In the SEED the hooks are in place from the factory (B2 edits those
files); on a live instance the phase adds them with a structural
guard — on a fresh start they are no-ops. Budget per file:

- cloudflared.yaml: `--metrics 0.0.0.0:2000` in args + containerPort
  (2 lines).
- jenkins/values.yaml: the metrics plugin in installPlugins (1 line;
  the choice and its VERIFY are in hooks.md).
- registry-config: a `debug: {addr: :5001, prometheus: {enabled:
  true}}` block (3 lines) + port 5001 in the Service (1 line, a
  second file).
- netpols (existing default-deny ingress rules that WOULD BLOCK the
  plumbing — the corner case that bites itself if it is not said
  out loud): jenkins-system (the plugin's port from observability),
  argocd (the metrics ports from observability), trivy-system (:4954
  from observability for blackbox's /healthz). One entry per file.
  Without this, `up == 0` with everything «healthy» — a scrape hole
  indistinguishable from an incident, in the very profile where
  holes are routine.

## 8. The phase's gates (measure the effect, not the deployment)

| gate | measures | why / diagnosis |
|---|---|---|
| obs-metricas-fluyen | a PromQL query to vmsingle: `count(up==1)` ≥ N expected targets | that vmagent is REALLY scraping; gate_diag: a list of `up==0` with labels — the target downed by a netpol shows up here and not 3 days later |
| obs-logs-fluyen | a query to vlogs: lines with a recent ts > 0 | Vector → vlogs, end to end |
| obs-eventos-ingestados | a count in vlogs-events ≥ the number of lines in gates.jsonl | the ingestion of step 11 landed (Synced does not prove data — the same lesson as F-B) |
| obs-cert-servido-medido | `probe_ssl_earliest_cert_expiry{instance=~"registry.*"} > 0` | B11: blackbox measures what is SERVED; >0 = a real handshake against the CA |
| obs-deadman-firing | vmalert's API: the Deadman alert in the firing state | the rule evaluates |
| obs-cadena-alerta-canal | a poll of the ntfy topic (`/aegis-alertas/json?poll=1`, with the operator's credential): the heartbeat ARRIVED | THE gate of the phase: the rule→Alertmanager→bridge→ntfy chain, complete. Watching the watchman is MEASURED at birth, not declared (Disease E) |
| obs-grafana-provisionado | /api/health + a count of datasources ≥ 3 (vmsingle, vlogs, vlogs-events), in-cluster via the Service | the provisioning from git landed; 0 datasources with a Healthy pod is exactly the failure that «Healthy» does not see |
| obs-grafana-tras-access | `edge_origin_responds` (lib/access.sh) against grafana.«dom» | it distinguishes «the origin answered» from «Access intercepted» — never a naked curl against a protected hostname (check 090) |
| obs-ntfy-publico-responde | an anonymous curl to ntfy.«dom»: reachable, and PUBLISHING without a token → 403 | the channel reaches the phone AND the deny-all is active (an open ntfy would be a spam relay with our domain on it) |

## 9. Corner cases

- The clock (WSL2 after suspend, §3.2): Vector stamps its own
  timestamp in addition to the emitter's — the «the collector
  orders, the emitter informs» contract is configured, not hoped
  for.
- `--only 85` re-run: gen_or_restore reuses credentials, the
  copies/entries have guards, the render is a no-op, argo_sync is
  idempotent, and the ingestion of the history re-uploads
  gates.jsonl (duplicates in vlogs-events: accepted and documented —
  it is the history of bootstraps, deduplicated at query time by
  ts+gate; the alternative, keeping state for «I have already
  ingested up to here», is more mechanism than the problem).
- `--reset-state` deletes gates.jsonl (known debt of stage C): the
  previous ingestion into vlogs-events SURVIVES — the phase turned
  fragile local state into remote history, as a side effect.
- A live instance whose appprojects.yaml diverged by hand: the
  guarded entry adds, never rewrites; if the file does not parse,
  the YAML is validated before writing (the inject_placeholder
  pattern).
- Multi-node hetzner: trivy-db-age and the RWO affinity (§2);
  thresholds already covered per profile.

## 10. Memory budget (honest, on a 16 GB node)

Expected RSS in steady state with this platform's load (dozens of
targets, a handful of builds/day) — not the limits, which reserve
nothing:

| component | expected RSS | proposed request/limit |
|---|---|---|
| vmsingle | 150–300 Mi | 128Mi / 512Mi |
| vmagent | 60–100 Mi | 64Mi / 256Mi |
| vmalert | 30–50 Mi | 32Mi / 128Mi |
| vlogs | 60–120 Mi | 64Mi / 256Mi |
| vlogs-events | 30–60 Mi | 32Mi / 128Mi |
| vector | 100–200 Mi | 128Mi / 512Mi |
| grafana | 150–250 Mi | 128Mi / 512Mi |
| alertmanager | 30–50 Mi | 32Mi / 128Mi |
| ntfy + bridge | 30–60 Mi | 32+16Mi / 128+64Mi |
| blackbox | 20–30 Mi | 16Mi / 64Mi |
| **total** | **~0.7–1.2 Gi** | requests ~0.7Gi / limits ~2.6Gi |

Disk: vmsingle 5Gi, vlogs 5Gi, vlogs-events 1Gi, ntfy 1Gi (~12Gi of
PVC). That is the real cost of no longer operating blind in dev, and
the operator accepted it with the number in front of him (design.md
§4.1). If the laptop contradicts it in practice, the cut is BY
PROFILE (new placeholders for requests), not by removing pieces —
first measure, then cut: now there is something to measure with.

## 11. B6's verification criterion (switching it on in the live instance)

`aegis init --only 85` over the instance that has history. B6 is
green when: (1) the 9 gates of §8 pass; (2) the heartbeat SOUNDS on
the operator's phone — the channel is tested on the real device, not
in a curl; (3) the operator opens grafana.«dom» CROSSING Access and
the 4 dashboards show live data (RUTA B6: «looking at real
dashboards» — the criterion is a question from design.md §1 answered
on screen, e.g. «where did the last bootstrap get stuck?» answered by
the gates dashboard); (4) `aegis verify` passes with the checks that
B2/B3 add. After that — and only after that — comes the B5→future
note (`aegis check` as a metric).

## 12. What this phase assumes and is NOT true TODAY (prerequisites)

- The seed does NOT have module.access: init/phases/25 demands the
  access_service_token_* outputs that only the INSTANCE's tofu
  produces (#76/#87 never came back to seed/platform/tofu/). The
  grafana.tf of §5 references policies of a module that does not
  exist in the seed. Settling that return is a prerequisite of B4
  (and a sibling of the «aegis-org is behind» that RUTA A7 already
  notes).
- Check 091 is scoped to organizations/ (§5).
- Stage C (capturing the init's human log) is still pending: this
  phase ingests gates.jsonl, not the lost stderr.
