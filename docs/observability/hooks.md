# Observabilidad v2 — puntos de enganche (la cañería puesta)

Dónde se enchufa la herramienta, por fase/componente. Cada hook
existe HOY como superficie estable. Desde el 2026-08-19 el stack
está decidido (design.md §4) y cada enchufe tiene consumidor
CONCRETO: vmagent (scrape de métricas), Vector (logs/eventos),
blackbox-exporter (sondas), VictoriaLogs (`vlogs` logs cortos /
`vlogs-eventos` retención larga). La fase que los aplica: 85
(fase-85.md §7). Instalar el stack NO requirió tocar las fases
previas — que era la promesa de este archivo.

| Componente | Hook existente | Qué expone | Consumidor concreto |
|------------|----------------|------------|---------------------|
| aegis-init | gates.jsonl (JSON-line por gate: ts, fase, gate, resultado, duración — `_gate_record`, common.sh:87-98) + .init-state/*.done (mtime) | duración/resultado por gate y por fase | fase 85 ingesta el gates.jsonl histórico a vlogs-eventos (curl al endpoint jsonline); B3 agrega el push best-effort por gate (≤3 líneas en `_gate_record`, `\|\| true` — el registro JAMÁS voltea un gate, y antes de la fase 85 el endpoint no existe) |
| ArgoCD | /metrics nativo (application-controller :8082, server :8083, repo-server :8084) | sync status, drift, latencias | scrape de vmagent; pide entry en la netpol de argocd (default-deny — fase-85 §7) |
| cert-manager | /metrics nativo (:9402) | certmanager_certificate_expiration_timestamp_seconds | scrape de vmagent — como CONTEXTO. La alerta B11 NO sale de acá: esta métrica mide el Secret (la declaración); lo servido lo mide blackbox (fila registry, y design.md §4.2b) |
| Traefik | /metrics nativo (entrypoint metrics del chart — VERIFICAR puerto/valores en 40.3.0) | RPS, códigos, latencia por router | scrape de vmagent |
| cloudflared | flag --metrics soportado por la imagen | reconexiones, conexiones activas del tunnel | vmagent; el flag + containerPort se agregan al Deployment (2 líneas — fase 85). Alerta e) con umbral por perfil |
| Kyverno | /metrics nativo (:8000) | admisiones permitidas/rechazadas por policy (con resource_namespace — VERIFICAR nombre exacto de la métrica en la versión pinneada), latencia webhook | scrape de vmagent; regla de vmalert: rechazos en org-* > 0 |
| Jenkins | plugin de métricas instalable por installPlugins | duración builds, cola, ejecutores | 1 línea en installPlugins (fase 85) + scrape de vmagent; entry en la netpol de jenkins-system. Se elige el plugin `prometheus` (expone /prometheus scrapeable sin API key; el plugin `metrics` a secas exige clave por query param — hostil a scrape). VERIFICAR shortname |
| pipeline (Jenkinsfile) | stage 'report' — log estructurado al final del build: `AEGIS_EVENT {json}` (digest, scan, firma, build, branch, ts) | el evento supply-chain completo | **CORREGIDO 2026-08-22**: se creía que Vector lo levantaría del stdout del pod, con CERO líneas nuevas. FALSO en un agente Kubernetes de Jenkins: la salida de un paso `sh` no va al stdout del contenedor — durable-task la escribe a un archivo y la manda por el canal de remoting a la consola del build, donde Vector no mira. El stream jenkins-build tuvo CERO filas desde siempre. Hoy el stage postea directo a vlogs-eventos, como gates.jsonl en la fase 85. Costo real: 6 líneas, no cero |
| Trivy server | /healthz + edad de la DB en el PVC (metadata.json) | vigía del vigía | blackbox sondea /healthz (entry en netpol de trivy-system); la EDAD no tiene métrica nativa — CronJob trivy-db-age (nuevo, lado observabilidad: monta el PVC, pushea la edad a vmsingle — fase-85 §2). El trivy en sí: 0 líneas tocadas |
| registry | /metrics de distribution (debug.prometheus en config) | pulls/pushes, errores auth | 3 líneas en el ConfigMap + 1 puerto en el Service (fase 85) → scrape de vmagent. Y blackbox sondea https://…:5000/v2/ validando contra el CA — de ahí sale probe_ssl_earliest_cert_expiry, LA alerta B11 (design.md §4.2b) |

Regla de la cañería, VERIFICADA contra el stack elegido: cada
enchufe es ≤3 líneas por archivo versionado ya existente —
cloudflared 2 (arg + puerto), Jenkins 1 (plugin), registry 3+1 en
dos archivos (ConfigMap + Service, cada uno dentro del tope),
netpols 1 entry por namespace cerrado, `_gate_record` 3. El
Jenkinsfile y el trivy-server: CERO. La regla aguanta; lo que es
MÁS que 3 líneas (blackbox, CronJob trivy-db-age, el stack mismo)
no es enchufe sino cañería nueva, y vive TODA del lado de
observability/ — ningún componente observado se rediseñó. Si un
enchufe futuro pide más que esto, el diseño falló: volver a
design.md antes de instalar nada.
