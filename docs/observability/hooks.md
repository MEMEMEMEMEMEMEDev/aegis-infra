# Observability v2 — the hook points (the plumbing laid)

Where the tool plugs in, by phase/component. Every hook exists
TODAY as a stable surface. Since 2026-08-19 the stack is decided
(design.md §4) and every hook has a CONCRETE consumer: vmagent
(metrics scrape), Vector (logs/events), blackbox-exporter (probes),
VictoriaLogs (`vlogs` for short-lived logs / `vlogs-events` for long
retention). The phase that applies them: 85 (fase-85.md §7).
Installing the stack did NOT require touching the previous phases —
which was this file's promise.

| Component | Existing hook | What it exposes | Concrete consumer |
|------------|----------------|------------|---------------------|
| aegis init | gates.jsonl (one JSON line per gate: ts, phase, gate, result, duration — `_gate_record`, common.sh:87-98) + .init-state/*.done (mtime) | duration/result per gate and per phase | phase 85 ingests the historical gates.jsonl into vlogs-events (a curl to the jsonline endpoint); B3 adds the best-effort push per gate (≤3 lines in `_gate_record`, `\|\| true` — the recording NEVER flips a gate, and before phase 85 the endpoint does not exist) |
| ArgoCD | native /metrics (application-controller :8082, server :8083, repo-server :8084) | sync status, drift, latencies | vmagent scrape; it needs an entry in argocd's netpol (default-deny — fase-85 §7) |
| cert-manager | native /metrics (:9402) | certmanager_certificate_expiration_timestamp_seconds | vmagent scrape — as CONTEXT. The B11 alert does NOT come from here: this metric measures the Secret (the declaration); what is served is measured by blackbox (the registry row, and design.md §4.2b) |
| Traefik | native /metrics (the chart's metrics entrypoint — VERIFY the port/values in 40.3.0) | RPS, codes, latency per router | vmagent scrape |
| cloudflared | the --metrics flag supported by the image | reconnections, active tunnel connections | vmagent; the flag + containerPort are added to the Deployment (2 lines — phase 85). Alert e) with a per-profile threshold |
| Kyverno | native /metrics (:8000) | admissions allowed/rejected per policy (with resource_namespace — VERIFY the exact metric name in the pinned version), webhook latency | vmagent scrape; a vmalert rule: rejections in org-* > 0 |
| Jenkins | a metrics plugin installable via installPlugins | build duration, queue, executors | 1 line in installPlugins (phase 85) + vmagent scrape; an entry in jenkins-system's netpol. The `prometheus` plugin is the one chosen (it exposes a scrapeable /prometheus with no API key; the plain `metrics` plugin demands a key as a query param — hostile to scraping). VERIFY the shortname |
| pipeline (Jenkinsfile) | the 'report' stage — a structured log at the end of the build: `AEGIS_EVENT {json}` (digest, scan, signature, build, branch, ts) | the complete supply-chain event | **CORRECTED 2026-08-22**: it was believed that Vector would pick it up from the pod's stdout, with ZERO new lines. FALSE on a Jenkins Kubernetes agent: the output of an `sh` step does not go to the container's stdout — durable-task writes it to a file and sends it over the remoting channel to the build's console, where Vector does not look. The jenkins-build stream had ZERO rows from the very beginning. Today the stage posts directly to vlogs-events, like gates.jsonl in phase 85. Real cost: 6 lines, not zero |
| Trivy server | /healthz + the age of the DB in the PVC (metadata.json) | the watchman's watchman | blackbox probes /healthz (an entry in trivy-system's netpol); the AGE has no native metric — the trivy-db-age CronJob (new, on the observability side: it mounts the PVC and pushes the age to vmsingle — fase-85 §2). Trivy itself: 0 lines touched |
| registry | distribution's /metrics (debug.prometheus in the config) | pulls/pushes, auth errors | 3 lines in the ConfigMap + 1 port in the Service (phase 85) → vmagent scrape. And blackbox probes https://…:5000/v2/ validating against the CA — that is where probe_ssl_earliest_cert_expiry comes from, THE B11 alert (design.md §4.2b) |

The plumbing rule, VERIFIED against the chosen stack: every hook is
≤3 lines in an already existing versioned file — cloudflared 2 (arg
+ port), Jenkins 1 (plugin), registry 3+1 across two files
(ConfigMap + Service, each within the cap), netpols 1 entry per
closed namespace, `_gate_record` 3. The Jenkinsfile and the
trivy-server: ZERO. The rule holds; what is MORE than 3 lines
(blackbox, the trivy-db-age CronJob, the stack itself) is not a hook
but new plumbing, and it all lives on the observability/ side — no
observed component was redesigned. If a future hook asks for more
than this, the design has failed: go back to design.md before
installing anything.
