# Fase 85 — observabilidad (diseño fino; B2/B3/B4 implementan ESTO)

Contrato: `init/phases/85-observability.sh`, después de
80-supply-chain. POR QUÉ 85: cuando corre, ya existe TODO lo que va
a observar (registry con TLS, Jenkins con builds, Kyverno en
Enforce, el túnel vivo) — una fase de observabilidad antes de sus
observados solo tendría gates triviales, y un gate que no puede
fallar no mide nada. Mismo esqueleto que toda fase: `set -euo
pipefail`, `source aegis-init.conf`, `platform_repo_sync` primero
(la fase MUTA el repo de plataforma), gates con `gate`/`gate_diag`,
idempotente para `--only 85` sobre instancia viva.

## 1. Layout en la semilla

```
seed/platform/k8s/base/observability/
  namespace.yaml            # ns `observability` EXPLÍCITO y PRIMERO
                            # (corrida #7 bug A: CreateNamespace no es
                            # confiable en apps kustomize — patrón
                            # registry-system, se iguala al que funciona)
  kustomization.yaml        # namespace + crudos + generator ksops
  secret-generator.yaml     # A7 LISTA EXPLÍCITA: grafana-admin.enc.yaml,
                            # ntfy-bridge-token.enc.yaml (los cifra la 85)
  ntfy.yaml                 # Deployment+Service+PVC 1Gi+ConfigMap (crudo)
  alertmanager.yaml         # Deployment+Service+ConfigMap (crudo)
  ntfy-bridge.yaml          # Deployment+Service del ntfy-alertmanager (crudo)
  blackbox.yaml             # Deployment+Service+ConfigMap módulos (crudo)
  configmap-aegis-ca.yaml   # PEM del CA para blackbox (placeholder
                            # __OBS_CA_PEM__, clase-GENERADO, dueño: fase 85)
  trivy-db-age.yaml         # CronJob — namespace trivy-system EXPLÍCITO
  reglas/                   # ConfigMaps de reglas de vmalert (deadman,
                            # b11, kyverno, trivy-db, cloudflared)
  dashboards/               # ConfigMaps con label grafana_dashboard
                            # (sidecar) — los 4 de design.md §4.4
  vmsingle/values.yaml      # -retentionPeriod=__OBS_RETENCION_METRICAS__
  vmagent/values.yaml       # scrape configs ENUMERADOS (A7-espíritu:
                            # target nuevo = entry nueva, no magia)
  vmalert/values.yaml       # notifier → alertmanager
  vlogs/values.yaml         # -retentionPeriod=__OBS_RETENCION_LOGS__
  vlogs-events/values.yaml # -retentionPeriod=1y (fijo ambos perfiles)
  vector/values.yaml        # kubernetes_logs → vlogs; route AEGIS_EVENT
                            # → vlogs-events (jsonline)
  grafana/values.yaml       # persistence OFF (design.md §4.1: sin PVC no
                            # hay dónde acumular estado-a-click),
                            # datasources provisionados, sidecar ON,
                            # admin.existingSecret=grafana-admin
```

POR QUÉ crudos y no charts para ntfy/alertmanager/puente/blackbox:
cada uno es UN contenedor con UN ConfigMap — un chart agregaría un
repo más a sourceRepos y una capa de values por pieza para ahorrar
~40 líneas de YAML legible. El precedente es registry.yaml: crudo,
denso y auditable de un vistazo. Los charts se reservan para lo que
de verdad los amortiza (la familia VM, Vector, Grafana).

Applications: `k8s/argocd-apps/observability.yaml` (multi-doc,
convenciones de core.yaml: ServerSideApply, selfHeal, prune
OMITIDO, labels aegis.dev/*, placeholders __GH_OWNER__/…):

| App | fuente | destino |
|---|---|---|
| observability-base | path k8s/base/observability (kustomize) | observability (+ trivy-system: el CronJob lleva ns explícito; el project aegis-platform permite '*') |
| vmsingle | chart victoria-metrics-single + $values | observability |
| vmagent | chart victoria-metrics-agent + $values | observability |
| vmalert | chart victoria-metrics-alert + $values | observability |
| vlogs | chart victoria-logs-single + $values | observability |
| vlogs-events | chart victoria-logs-single + $values (release aparte) | observability |
| vector | chart vector + $values | observability |
| grafana | chart grafana + $values | observability |

Charts y repos (versiones: VERIFICAR al implementar B2 — la casa
pinnea exacto o marca VERIFICAR, precedente `cilium_chart_version:
"VERIFICAR-ANTES-DE-HETZNER"` en group_vars):

| pieza | repo Helm | chart | targetRevision |
|---|---|---|---|
| vmsingle | https://victoriametrics.github.io/helm-charts | victoria-metrics-single | VERIFICAR |
| vmagent | ídem | victoria-metrics-agent | VERIFICAR |
| vmalert | ídem | victoria-metrics-alert | VERIFICAR |
| vlogs ×2 | ídem | victoria-logs-single | VERIFICAR |
| vector | https://helm.vector.dev | vector | VERIFICAR |
| grafana | https://grafana.github.io/helm-charts | grafana | VERIFICAR |

Imágenes de los crudos: binwiederhier/ntfy,
quay.io/prometheus/alertmanager, quay.io/prometheus/blackbox-exporter,
ntfy-alertmanager (VERIFICAR registry/imagen del puente — proyecto
xenrox), curlimages/curl o alpine/curl para el CronJob. Todas con
tag exacto, jamás latest (A42-espíritu).

sourceRepos NUEVOS en el AppProject aegis-platform
(k8s/bootstrap/appprojects.yaml, enumerados como los existentes —
NO '*'): los 3 repos Helm de arriba. Deben matchear repoURL exacto
de observability.yaml (regla escrita en el propio appprojects.yaml).

## 2. Decisiones por pieza (los porqués que no caben en la tabla)

- vmsingle: sin réplica, PVC 5Gi. La retención de §2 en un nodo
  solo cabe de sobra; escalar a cluster es problema del perfil
  hetzner FUTURO, no de hoy.
- vmagent y no scrape-directo-de-vmsingle: vmsingle puede scrapear
  solo, pero vmagent da relabeling y buffer en disco ante cortes —
  la red de dev se cae POR DISEÑO y perder el buffer sería perder
  exactamente las muestras del incidente.
- Dos VictoriaLogs: design.md §4.1 (retención global por instancia;
  filters por stream = enterprise, VERIFICAR).
- trivy-db-age: CronJob en trivy-system (el PVC de la DB es RWO y
  vive ahí) que lee el metadata de la DB y pushea
  `aegis_trivy_db_updated_timestamp_seconds` a
  vmsingle:/api/v1/import/prometheus. CASO BORDE RWO: en nodo único
  el segundo mount RWO co-localiza solo; en hetzner multi-nodo el
  CronJob necesita afinidad al nodo del trivy-server — anotar en el
  manifest, resolver al activar hetzner (VERIFICAR).
- blackbox valida la cadena CONTRA EL CA (configmap-aegis-ca): un
  probe con insecure_skip_verify daría expiry igual, pero dejaría
  pasar un cert EQUIVOCADO en verde — exactamente el -k que P2.4
  desterró de la fase 40. El módulo `registry_tls` acepta 401 como
  éxito (la auth del registry es posterior al handshake; el 401 ES
  la prueba de que el TLS y la auth están vivos — mismo criterio
  que el gate registry-tls-real).
- Alertmanager con emptyDir para silences: un silence es estado
  operativo efímero; perderlo en un restart re-alerta, que es el
  fallo SEGURO. PVC para silences sería estado-a-click con disfraz.

## 3. Secretos (A7, mismo camino que todos)

La fase 85 genera con `gen_or_restore` (re-run = mismo valor, bug 6)
y cifra con `make_enc_secret`:

- `grafana_admin_pass` → grafana-admin.enc.yaml (ns observability).
  Grafana queda tras Access PERO conserva su login: Access es la
  puerta, no la única cerradura (defensa en profundidad — la misma
  razón por la que argocd no quedó anónimo tras #76).
- `ntfy_bridge_token` → ntfy-bridge-token.enc.yaml: el token con el
  que el puente PUBLICA en ntfy.
- `ntfy_operador_pass`: credencial de la app del teléfono. NO va a
  Secret K8s (nadie en el cluster la consume — mismo razonamiento
  que access_st_id en la fase 25): vive en el store y se le muestra
  al operador UNA vez vía human_step para cargarla en la app.

Entries del secret-generator EN EL MISMO COMMIT que los .enc.yaml
(regla temporal, corrida #4), como entry REAL de lista
(yaml_lists_file — H4). Las 3 credenciales nuevas con receta de
rotación declarada (check 89 exige el inventario completo).

Los usuarios/ACL DENTRO de ntfy (deny-all por defecto; operador
lee, puente escribe en el topic `aegis-alertas`): VERIFICAR si la
versión pinneada soporta provisión declarativa por config
(`auth-users`); si sí, va al ConfigMap con los hashes; si no, la
fase 85 los crea vía `kubectl exec ntfy user add` con guard de
idempotencia — imperativo pero equivalente al htpasswd del
registry: estado de auth en PVC, generado por el init, recuperable
del store.

## 4. El perfil cruza a los manifests (el hueco, cerrado)

Decisión y porqué: design.md §4.3 (valores concretos por
placeholder, no un nombre-de-perfil que exigiría maquinaria de
templating nueva). Mecánica:

1. Tabla de derivación en `lib/common.sh` (junto a
   render_platform_placeholders, su único consumidor):

   | placeholder | greenfield | hetzner | consumidor |
   |---|---|---|---|
   | __AEGIS_PROFILE__ | greenfield | hetzner | external_labels de vmsingle/vmagent (identidad del dato) |
   | __OBS_RETENCION_METRICAS__ | 30d | 90d | vmsingle -retentionPeriod |
   | __OBS_RETENCION_LOGS__ | 7d | 30d | vlogs -retentionPeriod |
   | __OBS_CF_CAIDO_FOR__ | 30m | 5m | regla cloudflared (`for:`) |
   | __OBS_DEADMAN_REPEAT__ | 24h | 6h | route del deadman en Alertmanager (repeat_interval) |

   La retención de eventos (1y) NO es placeholder: no varía por
   perfil — un valor constante disfrazado de variable es una
   mentira de flexibilidad.

2. `_CONFIG_PLACEHOLDERS` suma los 5 nombres y el sed suma 5
   líneas; la verificación final existente («ningún clase-config
   sobrevive») los cubre GRATIS — un values a medio renderizar
   muere en el render, no como flag ilegible de vmsingle dos gates
   después.

3. Dónde corre: el render canónico de la fase 10 (arranque virgen:
   la semilla se copia y se renderiza entera) Y la propia fase 85
   tras traer archivos de la semilla (instancia viva: los archivos
   nuevos llegan con placeholders vivos — §6 paso 2). $PROFILE
   está disponible en ambos puntos (export global del init).

Casos borde: (a) cambiar --profile en un re-run NO re-renderiza
(el placeholder ya murió) — el perfil es identidad de nacimiento;
cambiarlo es editar los valores en git, documentado en el header de
la tabla. (b) el deadman de dev a 24h: la ausencia nocturna del
notebook NO es señal (dev intermitente por diseño); a 6h el
operador aprendería a ignorar el hueco — y una señal ignorada es la
Enfermedad E por el camino largo.

## 5. El borde: grafana y ntfy

- `edge.yaml` de la semilla suma `grafana` y `ntfy` a `plataforma:`
  — la lista de la que `bin/aegis-org borde` DERIVA
  public_hostnames (nadie edita main.tf a mano; la lección de
  ai.__ROOT_DOMAIN__).
- Access para Grafana: archivo NUEVO
  `tofu/modules/cloudflare-access/grafana.tf` con la application
  `grafana.${var.root_domain}` reusando las políticas existentes
  (operador + automatización). POR QUÉ archivo nuevo y no editar
  main.tf: HCL fusiona todos los .tf del directorio — un archivo
  nuevo se COPIA verbatim de la semilla a una instancia viva sin
  cirugía de merge (§6 paso 2), y el check 90 lo descubre solo (la
  lista de protegidos se deriva de los `domain` del módulo…
  VERIFICAR que el check barre *.tf y no solo main.tf; si no, es
  UNA línea del check).
- ntfy SIN Access — la app del teléfono no puede presentar service
  token ni pasar el login de Access. La cerradura es la auth
  PROPIA de ntfy (deny-all + ACL, §3). Y por ser la primera ruta
  pública de plataforma sin Access delante, su IngressRoute lleva
  los tres middlewares (cabeceras/ritmo/cuerpo) del check 91 —
  copiados del generador como hace el canary. NOTA: el check 91
  hoy solo barre platform/k8s/organizations/; extenderlo a
  observability es parte de B4 (si no, la copia sin comparador se
  desincroniza — exactamente lo que el check existe para impedir).
- IngressRoutes de grafana y ntfy: en observability-base (patrón
  argocd: la exposición vive junto al expuesto). La de grafana sin
  middlewares de tenant (va tras Access, como argocd/jenkins hoy).

## 6. Orden de ejecución de la fase (y sus porqués)

1. `platform_repo_sync` (CR-6: el clone puede estar detrás).
2. TRAER DE LA SEED lo que la instancia no tenga — la regla de
   RUTA.md («entra por semilla/+init/ o no entró») aplicada al
   caso instancia-viva, donde la fase 10 NO re-siembra (platform/
   con .git es la verdad):
   - copiar si faltan (archivos NUEVOS, verbatim):
     `k8s/base/observability/` entero,
     `k8s/argocd-apps/observability.yaml`,
     `tofu/modules/cloudflare-access/grafana.tf`;
   - entries guardadas en archivos EXISTENTES (guard estructural,
     jamás grep de mención — H4): sourceRepos ×3 en
     appprojects.yaml, `grafana`/`ntfy` en edge.yaml, y los
     enchufes de §7;
   - en arranque virgen todo esto es no-op: la semilla ya lo trae.
3. `render_platform_placeholders` (idempotente; renderiza los
   __OBS_*__ de los archivos recién copiados — §4.3).
4. Secretos (§3) + entries del generator; commit
   (`git_commit_if_changes`) + `git_push_verified` — ArgoCD lee del
   remoto, no del disco.
5. `kubectl apply -f k8s/bootstrap/appprojects.yaml` — los
   AppProjects son infra de bootstrap (clase C1, se aplican por
   kubectl como en la fase 35); sin los sourceRepos nuevos, el
   primer sync de un chart moriría con "not permitted".
6. El borde: `bin/aegis-org borde` (deriva public_hostnames) +
   `tofu-apply.sh -chdir=envs/cloudflare-tunnel apply` (crea
   CNAMEs, ingress del túnel y la Access App de grafana). Gate de
   resultado, no de intención (§8).
7. Enchufes ≤3 líneas (§7) + commit/push.
8. `argo_sync root 300` — root es MANUAL siempre (ADR-0012): las
   Applications nuevas nacen acá y no antes.
9. `argo_sync observability-base` primero (namespace + secretos +
   crudos: sin ns no hay dónde, sin Secret grafana no arranca) —
   con `argo_secrets_gate observability-base <timeout> <sha>` (F-B:
   Synced a la revisión RECIÉN pusheada, no a una vieja), luego los
   stores (`vmsingle`, `vlogs`, `vlogs-events`), luego colectores
   (`vmagent`, `vector`), luego `vmalert`, último `grafana` —
   productores antes que consumidores, el mismo orden-como-mecanismo
   de D5. `argo_sync` canónico de common.sh, jamás uno local.
10. Re-sync de los observados enchufados: `cloudflare-tunnel`,
    `jenkins`, `registry` (+ los netpol tocados viajan en sus apps).
    El de jenkins REINICIA el controller (plugin nuevo) — es el
    precio de una vez; el gate de Jenkins de la fase 50 no se
    re-corre, pero `wait_rollout jenkins-system` sí (convergencia
    antes de medir, la familia nº1).
11. Ingesta del histórico: `curl -T $AEGIS_STATE_DIR/gates.jsonl`
    al endpoint jsonline de vlogs-events (con _stream
    source=aegis-init). Best-effort NO: acá el endpoint DEBE
    existir — si falla, falla la fase (a diferencia del push por
    gate futuro de hooks.md, que es best-effort porque corre antes
    de que exista el destino).
12. Gates finales (§8).

## 7. Los enchufes que esta fase aplica (hooks.md, ejecutado)

En la SEED los enchufes quedan puestos de fábrica (B2 edita esos
archivos); en instancia viva la fase los agrega con guard
estructural — en fresh son no-op. Presupuesto por archivo:

- cloudflared.yaml: `--metrics 0.0.0.0:2000` en args + containerPort
  (2 líneas).
- jenkins/values.yaml: el plugin de métricas en installPlugins
  (1 línea; elección y VERIFICAR en hooks.md).
- registry-config: bloque `debug: {addr: :5001, prometheus:
  {enabled: true}}` (3 líneas) + puerto 5001 en el Service (1 línea,
  segundo archivo).
- netpols (default-deny ingress existentes que TAPARÍAN la
  cañería — el caso borde que se muerde solo si no se dice):
  jenkins-system (puerto del plugin desde observability), argocd
  (puertos de métricas desde observability), trivy-system (:4954
  desde observability para el /healthz de blackbox). Una entry por
  archivo. Sin esto, `up == 0` con todo «sano» — un agujero de
  scrape indistinguible de un incidente, en el perfil donde los
  agujeros son rutina.

## 8. Gates de la fase (medir el efecto, no el deployment)

| gate | mide | por qué / diagnóstico |
|---|---|---|
| obs-metricas-fluyen | query PromQL a vmsingle: `count(up==1)` ≥ N targets esperados | que vmagent scrapea DE VERDAD; gate_diag: lista de `up==0` con labels — el target caído por netpol se ve acá y no 3 días después |
| obs-logs-fluyen | query a vlogs: líneas con ts reciente > 0 | Vector → vlogs de punta a punta |
| obs-eventos-ingestados | count en vlogs-events ≥ nº de líneas de gates.jsonl | la ingesta del paso 11 aterrizó (Synced no prueba datos — misma lección que F-B) |
| obs-cert-servido-medido | `probe_ssl_earliest_cert_expiry{instance=~"registry.*"} > 0` | B11: el blackbox mide lo SERVIDO; >0 = handshake real contra el CA |
| obs-deadman-firing | API de vmalert: alerta Deadman en estado firing | la regla evalúa |
| obs-cadena-alerta-canal | poll al topic de ntfy (`/aegis-alertas/json?poll=1`, con la credencial del operador): el heartbeat LLEGÓ | EL gate de la fase: cadena regla→Alertmanager→puente→ntfy completa. Vigilar al vigía se MIDE en el nacimiento, no se declara (Enfermedad E) |
| obs-grafana-provisionado | /api/health + count de datasources ≥ 3 (vmsingle, vlogs, vlogs-events), in-cluster vía Service | el provisioning desde git aterrizó; 0 datasources con pod Healthy es exactamente el fallo que «Healthy» no ve |
| obs-grafana-tras-access | `edge_origen_responde` (lib/access.sh) contra grafana.«dom» | distingue «origen contestó» de «Access interceptó» — jamás un curl desnudo contra hostname protegido (check 90) |
| obs-ntfy-publico-responde | curl anónimo a ntfy.«dom»: alcanzable, y PUBLICAR sin token → 403 | el canal llega al teléfono Y el deny-all está activo (un ntfy abierto sería spam-relay con nuestro dominio) |

## 9. Casos borde

- Reloj (WSL2 post-suspend, §3.2): Vector estampa su timestamp
  además del emisor — el contrato «colector ordena, emisor informa»
  se configura, no se espera.
- --only 85 re-corrido: gen_or_restore reusa credenciales, las
  copias/entries tienen guard, el render es no-op, argo_sync es
  idempotente, la ingesta del histórico re-sube el gates.jsonl
  (duplicados en vlogs-events: aceptado y documentado — es
  historia de bootstraps, se deduplica en query por ts+gate; la
  alternativa, estado de «ya ingesté hasta acá», es más mecanismo
  que el problema).
- `--reset-state` borra gates.jsonl (deuda conocida de etapa C):
  la ingesta previa en vlogs-events SOBREVIVE — la fase convirtió
  el estado local frágil en historia remota, de paso.
- Instancia viva cuyo appprojects.yaml divergió a mano: la entry
  guardada agrega, nunca reescribe; si el archivo no parsea, el
  yaml se valida antes de escribir (patrón inject_placeholder).
- hetzner multi-nodo: trivy-db-age y la afinidad RWO (§2);
  umbrales ya cubiertos por perfil.

## 10. Presupuesto de memoria (honesto, nodo de 16 GB)

RSS esperado en régimen con la carga de esta plataforma (decenas de
targets, un puñado de builds/día) — no los limits, que no reservan:

| componente | RSS esperado | request/limit propuestos |
|---|---|---|
| vmsingle | 150–300 Mi | 128Mi / 512Mi |
| vmagent | 60–100 Mi | 64Mi / 256Mi |
| vmalert | 30–50 Mi | 32Mi / 128Mi |
| vlogs | 60–120 Mi | 64Mi / 256Mi |
| vlogs-events | 30–60 Mi | 32Mi / 128Mi |
| vector | 100–200 Mi | 128Mi / 512Mi |
| grafana | 150–250 Mi | 128Mi / 512Mi |
| alertmanager | 30–50 Mi | 32Mi / 128Mi |
| ntfy + puente | 30–60 Mi | 32+16Mi / 128+64Mi |
| blackbox | 20–30 Mi | 16Mi / 64Mi |
| **total** | **~0.7–1.2 Gi** | requests ~0.7Gi / limits ~2.6Gi |

Disco: vmsingle 5Gi, vlogs 5Gi, vlogs-events 1Gi, ntfy 1Gi (~12Gi
PVC). Es el costo real de dejar de operar ciego en dev y el
operador lo aceptó con el número delante (design.md §4.1). Si el
notebook lo desmiente en la práctica, el recorte es por PERFIL
(placeholders nuevos de requests), no por sacar piezas — primero
medir, después recortar: ahora hay con qué.

## 11. Criterio de verificación de B6 (encendido en la instancia viva)

`aegis-init --only 85` sobre la instancia con historia. B6 es verde
cuando: (1) los 9 gates de §8 pasan; (2) el heartbeat SUENA en el
teléfono del operador — el canal se prueba en el dispositivo real,
no en un curl; (3) el operador abre grafana.«dom» ATRAVESANDO
Access y los 4 dashboards muestran datos vivos (RUTA B6: «mirando
dashboards reales» — el criterio es la pregunta de design.md §1
respondida en pantalla, p.ej. «¿dónde se atascó el último
bootstrap?» contestada por el dashboard de gates); (4)
verify-static pasa con los checks que B2/B3 agreguen. Después — y
solo después — entra la nota B5→futuro (aegis-chequeo como métrica).

## 12. Lo que esta fase asume y HOY no es cierto (prerequisitos)

- La semilla NO tiene module.access: init/phases/25 exige los
  outputs access_service_token_* que solo el tofu de la INSTANCIA
  produce (#76/#87 no volvieron a seed/platform/tofu/). El
  grafana.tf de §5 referencia políticas de un módulo que en la
  semilla no existe. Saldar ese retorno es prerequisito de B4 (y
  hermano del «aegis-org atrasado» que RUTA A7 ya anota).
- check 91 acotado a organizations/ (§5).
- Etapa C (captura del log humano del init) sigue pendiente: esta
  fase ingesta gates.jsonl, no el stderr perdido.
