# Observability v2 — the data design, now WITH a tool

A history of the scope: this document was born as «the plumbing and
the blueprint, without the taps» — tool-agnostic DATA contracts,
zero installation. That design is preserved INTACT below (§1–§3),
because the tool was chosen AFTERWARDS and against it — that was
the whole point. Since 2026-08-19 the tool IS decided (a
conversation with the operator; §4). The execution plan lives in
RUTA.md track B; the fine design of the installation, in
observability/fase-85.md; the hook points, in hooks.md. §1–§3
remain the yardstick: if a config in the stack contradicts a data
contract from here, the config is wrong, not the contract.

## 1. What is observed (why, and what question it answers)

Layer 1 — The bootstrap itself (the init as an observed system):
- Duration per phase, gates passed/failed, human pauses and their
  duration. Question: "where does a bootstrap get stuck?" — it is
  the datum that validates or refutes the aspirational "~1 h" of
  the DR.
- Source: the init ALREADY emits it (a structured log per phase +
  .init-state markers with filesystem timestamps). Zero extra work.

Layer 2 — Platform health (what is checked by hand today):
- ArgoCD: apps Synced/Healthy, non-cosmetic OutOfSync drift, age of
  the last sync. Question: "are git and the cluster diverging?"
- cert-manager: days-to-expiry per Certificate. THE MOST VALUABLE
  METRIC of the platform: debt B11 (a manual restart of the
  registry at ~60d) today depends on human memory — an alert at 30d
  makes it operable without Reloader.
- cloudflared: reconnections/hour. A CORNER CASE of the datum: the
  dev environment is intermittent BY DESIGN (internet from the
  phone) — a high restartCount = healthy reconnection. The useful
  signal is NOT "there was a restart" but "it failed to reconnect
  within N min". Threshold per profile: dev tolerant, hetzner
  strict.
- Kyverno: REJECTED admissions in tenant namespaces (each one is
  either an attack or a broken pipeline — both urgent), webhook
  latency (it is on the critical path of EVERY tenant pod).

Layer 3 — Supply chain (the events that tell the story):
- Per build: digest, scan result (CVEs by severity), signature
  OK/failure, duration per stage. Question: "what is running in
  prod and which build did it come out of?" — the
  build→digest→pod traceability.
- Trivy server: the age of the DB (if it does not update, the scan
  lies silently — it is the watchman of pin A42, and the watchman
  has to be watched).

## 2. Where the data lives (and how much of it)

| Datum | Form | Retention | Cardinality note |
|------|-------|-----------|----------------------|
| init logs | one file per run in the workspace | forever (it is small, it is history) | n/a |
| platform metrics | scrape of the /metrics ALREADY exposed | 30d dev / 90d hetzner | labels: app, ns. NEVER a digest or a build-id as a metric label (cardinality explodes — that is a log/event, not a metric) |
| supply-chain events | append-only JSON lines (bucket/PVC) | 1 year (audit) | natural key: digest |
| pod logs | stdout → a future collector | 7d dev / 30d hetzner | NEVER Secret payloads: the pipelines no longer print values (secrets convention §5) — the collector inherits that guarantee, it does not create it |

The key data decision: metrics and events SEPARATE. The temptation
to put the digest in as a Prometheus label is the classic mistake —
the digest is EVENT identity (a structured log), not a metric
dimension.

## 3. Corner cases in the treatment of data

1. Secrets in logs: the guarantee is UPSTREAM (the convention of
   not printing them), the collector does not filter — a filter in
   the collector would be inverse TOFU: trusting that the regex
   catches it. If a secret reaches a log, it is an incident at the
   source, and dev's short retention (7d) bounds the damage.
2. The clock: WSL2 can drift after suspend — events carry a
   timestamp from the emitter AND from the collector; in a conflict,
   the collector's orders them, the emitter's informs.
3. Dev intermittency: scrape gaps are NOT incidents; future
   dashboards must distinguish "no data" from "zero".
4. Tenant cardinality: ns labels are bounded by design
   (multi-tenancy per ns) — the day there are N tenants, the cost of
   metrics scales with N, not with N×apps (app labels stay inside
   the tenant).

## 4. What was still to be decided — DECIDED (2026-08-19)

This section used to be called «what is NOT decided yet». It was
decided in conversation with the operator; here each decision is
recorded with its why. Reopening them takes new evidence, not a new
opinion.

### 4.1 The stack

- Metrics: the VictoriaMetrics family — vmsingle (store+query),
  vmagent (scrape), vmalert (rules). WHY: one binary per role, no
  operator and no CRDs of its own — an operator adds a controller
  and types that a single node does not amortise, and its
  intermediate objects make ArgoCD's diff unreadable. Flat charts →
  Deployments that read as they are in git (I1). Full
  PromQL/scrape-format compatibility: the /metrics of hooks.md go in
  with no translation.
- Logs and events: VictoriaLogs. Chosen OVER Loki: a single binary,
  NATIVE JSON-lines ingestion — the Jenkinsfile's AEGIS_EVENT events
  and the init's gates.jsonl ALREADY ARE JSON lines, the format of
  §2 goes in with no adapter — and without Loki's
  object-storage/multi-tenant complexity, which on a single node is
  surface with no use (I4).
- TWO instances of VictoriaLogs, not one (a derived decision, and it
  has to be said): retention in VictoriaLogs OSS is GLOBAL per
  instance (per-stream retention filters are an enterprise feature —
  VERIFY when pinning the version). §2 demands 7d/30d for pod logs
  AND 1 year for supply-chain events: a single instance at 1 year
  would violate the short retention of logs — and its why (§3.1: the
  short retention BOUNDS the damage of a leaked secret). Two
  instances (`vlogs` for logs, `vlogs-events` for events +
  gates.jsonl) are the metrics≠events≠logs separation of §2 made
  physical: each datum with ITS retention, without depending on paid
  features or on query discipline.
- Collector: Vector (one DaemonSet; on the single node, one pod). It
  reads pods' stdout → vlogs. Its routing of `AEGIS_EVENT ` to
  vlogs-events stays configured and does no harm, but it is NOT how
  the event arrives: **the output of a Jenkins `sh` step never
  touches the pod's stdout** — durable-task writes it to a file and
  transmits it over the remoting channel to the build's console, out
  of Vector's sight. The supply-chain event earns its 1-year
  retention with a direct POST from the `report` stage, just like
  gates.jsonl in phase 85. Corrected on 2026-08-22, after the two
  supply-chain panels had spent their entire lives empty with real
  builds running.
- Viewer: Grafana provisioned 100% FROM GIT — datasources by
  provisioning, dashboards by a sidecar reading ConfigMaps from the
  repo. NOTHING configured by clicking: a clicked dashboard is an
  invisible orphan — it is not in git, ArgoCD does not evaluate it,
  it dies with the pod and nobody knows it ever existed. It is baked
  in as a constraint: Grafana with NO persistence — click-state has
  nowhere to live, so it cannot accumulate (the constraint as
  mechanism, not as a rule of conduct).
- Channel: SELF-HOSTED ntfy (a small pod + a phone app + a hostname
  through the tunnel). WHY self-hosted: the channel for «the
  platform is broken» cannot depend on a free third-party SaaS with
  guessable topics; and WHY ntfy: it is the only channel that
  reaches the operator's phone without an app store of our own or a
  new account. It goes OUTSIDE Access (the phone app cannot present
  a service token) with ntfy's OWN deny-all auth — the detail is in
  fase-85.md §5.
- Alert chain: vmalert (evaluates) → Alertmanager
  (groups/routes/silences) → the ntfy bridge → ntfy → phone. The
  bridge exists because vmalert speaks Alertmanager's protocol and
  ntfy speaks plain HTTP: without the bridge, Alertmanager's webhook
  would reach ntfy as unreadable raw JSON. That is two more small
  containers and they are accepted WITH eyes open: the long chain is
  exactly what the deadman (§4.2a) watches end to end — every extra
  link is covered by the same alert that justifies its existence.
- COMPLETE IN BOTH PROFILES (greenfield and hetzner). An explicit
  decision by the operator knowing that the dev laptop has 16 GB: to
  stop operating blind is worth it also —above all— in dev, which is
  where things break first; and a stack that only runs on hetzner is
  never tested in the clean-room (stage D). An honest memory budget:
  fase-85.md §10 (~1 GiB real).

### 4.2 Foundational alerts (the WHAT of §1, now with a threshold and a channel)

a) DEADMAN — a rule that is ALWAYS firing (a constant expr) and
   reaches ntfy at a fixed cadence. Its value is not the message: it
   is its ABSENCE. If the heartbeat stops arriving at the phone, the
   metric→rule→Alertmanager→bridge→ntfy→app chain is broken at SOME
   link — and that is known without looking at anything. It is
   «watching the watchman» (the house's Disease E doctrine): an
   alerting system without a deadman is a gate that can stay green
   while switched off. Cadence per profile (fase-85.md §4): in dev
   the laptop sleeps by design and a night-time absence is not a
   signal.
b) B11 FOR REAL — blackbox-exporter probing the registry's :5000 and
   alerting on probe_ssl_earliest_cert_expiry, that is, on the
   SERVED certificate. The why deserves the space: cert-manager
   renews the registry-tls Secret at 60d, but the registry's pod
   does NOT restart (debt B11, registry.yaml documents it) — at that
   moment the Certificate/Secret metric
   (certmanager_certificate_expiration_...) jumps to 90d and says
   «all fine» while the pod keeps serving the old cert that dies in
   30d. Measuring the Secret is measuring the DECLARATION, not what
   is served — the same disease as the edge gate of #87 (Cloudflare's
   302 that read as «the cluster responds»). The cert-manager metric
   is kept as context; the ALERT comes out of the real TLS
   handshake.
c) Kyverno: REJECTED admissions in tenant namespaces (org-*) > 0.
   Each one is an attack or a broken pipeline — both urgent (§1
   layer 2). A threshold of 0 on purpose: in healthy operation this
   number IS zero, and a threshold >0 would only teach people to
   ignore it.
d) Age of the Trivy DB > 48h. The watchman's watchman: if the DB
   does not update, every «green» scan lies in silence — pin A42
   becomes faith. There is no native metric; it is derived (fase-85
   §2: a CronJob that reads the DB's metadata and pushes it to
   vmsingle).
e) cloudflared «failed to reconnect within N min» — the signal of §1
   layer 2 exactly as written: NOT restarts (healthy reconnection in
   dev), but active connections == 0 SUSTAINED. Threshold PER
   PROFILE: dev is intermittent BY DESIGN (internet from the phone,
   a laptop that suspends) — scrape gaps are NOT incidents (§3.3) —
   so dev tolerates 30 min; hetzner, 5. The value crosses over
   through a profile placeholder (§4.3).

### 4.3 PROFILE crosses over into the manifests

The hole: PROFILE (greenfield|hetzner) today lives ONLY in the
init's process (the --profile flag → $PROFILE) and dies at the
process boundary — no manifest knows which profile it runs in, and
§2 declares retentions PER PROFILE. The decision: config-class
placeholders BY VALUE (__OBS_RETENCION_METRICAS__,
__OBS_RETENCION_LOGS__, __OBS_CF_CAIDO_FOR__,
__OBS_DEADMAN_REPEAT__), derived from $PROFILE by a table in the
init and rendered by render_platform_placeholders — the same single
owner that already renders __ROOT_DOMAIN__ and verifies that none
survives. Plus __AEGIS_PROFILE__ (the name) as an external_label on
the metrics: identity, not behaviour.

WHY values and not just the name: a `perfil: hetzner` in a static
YAML is a fork that SOMETHING would have to interpret — a Helm if,
a kustomize overlay — and that machinery does not exist in the seed;
adding it for this would be a redesign (it would violate hooks.md's
rule). Concrete values keep the manifests declarative and the
existing render is enough: one more line per placeholder in the sed,
zero new mechanism. The name travels as well, as a label, so that
the DATA says which profile it came out of (a dashboard can
distinguish «no data» from «zero» according to the profile's
semantics, §3.3). A corner case baked in: the profile is identity AT
BIRTH — after the render the placeholder is dead and changing
profile on a live instance means editing values in git, not re-running
the init. The mechanics and the value table: fase-85.md §4.

### 4.4 Dashboards

They are derived from the questions of §1, as was foreseen — now
with a viewer. Initial set (ConfigMaps in git, sidecar): bootstrap
(gates.jsonl: duration/result per phase and per run), platform
(ArgoCD sync/drift, certs, cloudflared, Kyverno), supply-chain
(events: builds→digest→scan→signature, Trivy DB age), edge (Traefik
RPS/codes/latency). None is born from a click (§4.1).

### 4.5 What is STILL undecided (honestly)

- The human log per init run: §2 lists it as «one file per run» but
  TODAY a run's stderr is not captured (stage C of RUTA.md;
  gates.jsonl DOES exist and is what gets ingested).
- `aegis check` as a metric pushed to the store: it goes in when B6
  is green, not before (a note in RUTA.md track B).
- node-exporter / kube-state-metrics: DEFERRED on purpose. The
  kubelet's cAdvisor already gives CPU/mem per container via a
  scrape with vmagent's ServiceAccount; the HOST's disk goes without
  a metric until it hurts — noted, not forgotten (I4: every new
  component earns its place).
