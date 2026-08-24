# Observabilidad v2 — diseño de datos, ahora CON herramienta

Historia del alcance: este documento nació como «la cañería y el
plano, sin las canillas» — contratos de DATOS tool-agnostic, cero
instalación. Ese diseño se conserva ÍNTEGRO abajo (§1–§3), porque
la herramienta se eligió DESPUÉS y contra él — ese era el punto.
Desde el 2026-08-19 la herramienta ESTÁ decidida (charla con el
operador; §4). El plan de ejecución vive en RUTA.md pista B; el
diseño fino de la instalación, en observability/fase-85.md; los
puntos de enganche, en hooks.md. Los §1–§3 siguen siendo la vara:
si un config del stack contradice un contrato de datos de acá, el
config está mal, no el contrato.

## 1. Qué se observa (por qué, y qué pregunta responde)

Capa 1 — El bootstrap mismo (el init como sistema observado):
- Duración por fase, gates pasados/fallados, pausas humanas y su
  duración. Pregunta: "¿dónde se atasca un bootstrap?" — es el dato
  que valida o refuta el "~1 h" aspiracional del DR.
- Fuente: el init YA la emite (log estructurado por fase + markers
  .init-state con timestamps del filesystem). Cero trabajo extra.

Capa 2 — Salud de plataforma (lo que hoy se chequea a mano):
- ArgoCD: apps Synced/Healthy, drift OutOfSync no-cosmético, edad
  del último sync. Pregunta: "¿git y cluster divergen?"
- cert-manager: días-a-expiración por Certificate. LA MÉTRICA MÁS
  VALIOSA de la plataforma: la deuda B11 (restart manual del
  registry a ~60d) hoy depende de memoria humana — una alerta a
  30d la vuelve operable sin Reloader.
- cloudflared: reconexiones/hora. CASO BORDE del dato: el entorno
  dev es intermitente POR DISEÑO (internet del teléfono) —
  restartCount alto = reconexión sana. La señal útil NO es "hubo
  restart" sino "no logró reconectar en N min". Umbral por perfil:
  dev tolerante, hetzner estricto.
- Kyverno: admisiones RECHAZADAS en namespaces tenant (cada una es o un
  ataque o un pipeline roto — ambas urgentes), latencia del
  webhook (está en el camino crítico de TODO pod del tenant).

Capa 3 — Supply-chain (los eventos que cuentan la historia):
- Por build: digest, resultado del scan (CVEs por severidad),
  firma OK/fallo, duración por stage. Pregunta: "¿qué corre en
  prod y de qué build salió?" — la trazabilidad build→digest→pod.
- Trivy server: edad de la DB (si no se actualiza, el scan miente
  silenciosamente — es el vigía del pin A42, hay que vigilar al
  vigía).

## 2. Dónde viven los datos (y cuánto)

| Dato | Forma | Retención | Nota de cardinalidad |
|------|-------|-----------|----------------------|
| logs de init | archivo por run en el workspace | para siempre (chico, es historia) | n/a |
| métricas plataforma | scrape de /metrics YA expuestos | 30d dev / 90d hetzner | labels: app, ns. JAMÁS digest ni build-id como label de métrica (cardinalidad explota — eso es log/evento, no métrica) |
| eventos supply-chain | JSON lines append-only (bucket/PVC) | 1 año (auditoría) | clave natural: digest |
| logs de pods | stdout → colector futuro | 7d dev / 30d hetzner | NUNCA payloads de Secrets: los pipelines ya no imprimen valores (convención secrets §5) — el colector hereda esa garantía, no la crea |

Decisión de datos clave: métricas y eventos SEPARADOS. La
tentación de meter el digest como label de Prometheus es el error
clásico — el digest es identidad de EVENTO (log estructurado), no
dimensión de métrica.

## 3. Casos borde del tratamiento de datos

1. Secretos en logs: la garantía es UPSTREAM (convención de no
   imprimir), el colector no filtra — un filtro en el colector
   sería TOFU inverso: confianza en que el regex atrapa. Si un
   secreto llega a un log, es incidente de la fuente, y la
   retención corta de dev (7d) acota el daño.
2. Reloj: WSL2 puede driftear post-suspend — los eventos llevan
   timestamp del emisor Y del colector; ante conflicto, el del
   colector ordena, el del emisor informa.
3. Intermitencia dev: los huecos de scrape NO son incidentes;
   los dashboards futuros deben distinguir "sin dato" de "cero".
4. Cardinalidad de tenants: labels de ns están acotados por diseño
   (multi-tenancy por ns) — el día que haya N tenants, el costo
   de métricas escala con N, no con N×apps (labels de app quedan
   dentro del tenant).

## 4. Lo que estaba por decidir — DECIDIDO (2026-08-19)

Esta sección se llamaba «lo que NO se decide todavía». Se decidió
en charla con el operador; acá queda cada decisión con su porqué.
Reabrirlas pide evidencia nueva, no opinión nueva.

### 4.1 El stack

- Métricas: familia VictoriaMetrics — vmsingle (store+query),
  vmagent (scrape), vmalert (reglas). POR QUÉ: un binario por rol,
  sin operator ni CRDs propios — un operator agrega un controlador
  y tipos que un nodo solo no amortiza, y sus objetos intermedios
  vuelven ilegible el diff de ArgoCD. Charts planos → Deployments
  que se leen tal cual en git (I1). Compatibilidad PromQL/formato
  de scrape total: los /metrics de hooks.md entran sin traducción.
- Logs y eventos: VictoriaLogs. Elegido SOBRE Loki: un solo
  binario, ingesta JSON-lines NATIVA — los eventos AEGIS_EVENT del
  Jenkinsfile y el gates.jsonl del init YA SON JSON lines, el
  formato de §2 entra sin adaptador — y sin la complejidad
  object-storage/multi-tenant de Loki, que en un nodo solo es
  superficie sin uso (I4).
- DOS instancias de VictoriaLogs, no una (decisión derivada, y hay
  que decirla): la retención en VictoriaLogs OSS es GLOBAL por
  instancia (los retention filters por stream son feature
  enterprise — VERIFICAR al pinnear versión). §2 exige 7d/30d para
  logs de pods Y 1 año para eventos supply-chain: una sola
  instancia a 1 año violaría la retención corta de logs — y su
  porqué (§3.1: la retención corta ACOTA el daño de un secreto
  filtrado). Dos instancias (`vlogs` para logs, `vlogs-events`
  para eventos + gates.jsonl) son la separación métricas≠eventos≠
  logs de §2 hecha física: cada dato con SU retención, sin
  depender de features pagas ni de disciplina de queries.
- Colector: Vector (un DaemonSet; en el nodo único, un pod). Lee
  stdout de pods → vlogs. Su ruteo de `AEGIS_EVENT ` a vlogs-events
  sigue configurado y no estorba, pero NO es por donde llega el
  evento: **la salida de un paso `sh` de Jenkins nunca toca el stdout
  del pod** — durable-task la escribe a un archivo y la transmite por
  el canal de remoting hasta la consola del build, fuera de la vista
  de Vector. El evento supply-chain gana su retención de 1 año con un
  POST directo desde el stage `report`, igual que gates.jsonl en la
  fase 85. Corregido el 2026-08-22, después de que los dos paneles de
  supply-chain pasaran su vida entera vacíos con builds reales
  corriendo.
- Visor: Grafana provisionado 100% DESDE GIT — datasources por
  provisioning, dashboards por sidecar leyendo ConfigMaps del
  repo. NADA configurado a click: un dashboard clickeado es un
  huérfano invisible — no está en git, no lo evalúa ArgoCD, muere
  con el pod y nadie sabe que existió. Se hornea como restricción:
  Grafana SIN persistence — el estado-a-click no tiene dónde
  vivir, así que no puede acumularse (la restricción como
  mecanismo, no como regla de conducta).
- Canal: ntfy AUTOHOSPEDADO (un pod chico + app de teléfono +
  hostname por el túnel). POR QUÉ autohospedado: el canal de «la
  plataforma está rota» no puede depender de un SaaS gratuito de
  terceros con topics adivinables; y POR QUÉ ntfy: es el único
  canal que llega al teléfono del operador sin app-store propia ni
  cuenta nueva. Va FUERA de Access (la app del teléfono no puede
  presentar service token) con auth PROPIA de ntfy deny-all — el
  detalle en fase-85.md §5.
- Cadena de alerta: vmalert (evalúa) → Alertmanager
  (agrupa/enruta/silencia) → puente ntfy-alertmanager → ntfy →
  teléfono. El puente existe porque vmalert habla el protocolo de
  Alertmanager y ntfy habla HTTP plano: sin puente, el webhook de
  Alertmanager llegaría a ntfy como JSON crudo ilegible. Son dos
  contenedores chicos más y se aceptan CON los ojos abiertos: la
  cadena larga es exactamente lo que el deadman (§4.2a) vigila de
  punta a punta — cada eslabón extra está cubierto por la misma
  alerta que justifica su existencia.
- COMPLETO EN AMBOS PERFILES (greenfield y hetzner). Decisión
  explícita del operador sabiendo que el notebook de dev tiene
  16 GB: dejar de operar ciego vale también —sobre todo— en dev,
  que es donde las cosas se rompen primero; y un stack que solo
  corre en hetzner jamás se prueba en el clean-room (etapa D).
  Presupuesto de memoria honesto: fase-85.md §10 (~1 GiB real).

### 4.2 Alertas fundacionales (el QUÉ de §1, ahora con umbral y canal)

a) DEADMAN — una regla que SIEMPRE está firing (expr constante) y
   llega a ntfy con cadencia fija. Su valor no es el mensaje: es
   su AUSENCIA. Si el heartbeat deja de llegar al teléfono, la
   cadena métrica→regla→Alertmanager→puente→ntfy→app está rota en
   ALGÚN eslabón — y eso se sabe sin mirar nada. Es «vigilar al
   vigía» (doctrina Enfermedad E de la casa): un sistema de
   alertas sin deadman es un gate que puede quedar verde apagado.
   Cadencia por perfil (fase-85.md §4): en dev el notebook duerme
   por diseño y la ausencia nocturna no es señal.
b) B11 DE VERDAD — blackbox-exporter sondeando el :5000 del
   registry y alertando por probe_ssl_earliest_cert_expiry, o sea
   por el certificado SERVIDO. El porqué merece el espacio:
   cert-manager renueva el Secret registry-tls a los 60d, pero el
   pod del registry NO reinicia (deuda B11, registry.yaml lo
   documenta) — en ese momento la métrica del
   Certificate/Secret (certmanager_certificate_expiration_...)
   salta a 90d y dice «todo bien» mientras el pod sigue sirviendo
   el cert viejo que muere en 30d. Medir el Secret es medir la
   DECLARACIÓN, no lo servido — la misma enfermedad del gate del
   borde de #87 (el 302 de Cloudflare que se leía como «el cluster
   responde»). La métrica de cert-manager se conserva como
   contexto; la ALERTA sale del handshake TLS real.
c) Kyverno: admisiones RECHAZADAS en namespaces de tenant
   (org-*) > 0. Cada una es un ataque o un pipeline roto — ambas
   urgentes (§1 capa 2). Umbral 0 a propósito: en operación sana
   este número ES cero, y un umbral >0 solo enseñaría a ignorarlo.
d) Edad de la DB de Trivy > 48h. El vigía del vigía: si la DB no
   se actualiza, cada scan «verde» miente en silencio — el pin A42
   pasa a ser fe. No hay métrica nativa; se deriva (fase-85 §2:
   CronJob que lee metadata de la DB y la pushea a vmsingle).
e) cloudflared «no logró reconectar en N min» — la señal de §1
   capa 2 tal cual: NO restarts (reconexión sana en dev), sino
   conexiones activas == 0 SOSTENIDO. Umbral POR PERFIL: dev es
   intermitente POR DISEÑO (internet del teléfono, notebook que
   suspende) — huecos de scrape NO son incidentes (§3.3) — así que
   dev tolera 30 min; hetzner, 5. El valor cruza por placeholder
   de perfil (§4.3).

### 4.3 PROFILE cruza a los manifests

El hueco: PROFILE (greenfield|hetzner) hoy vive SOLO en el proceso
del init (flag --profile → $PROFILE) y muere en el límite del
proceso — ningún manifest sabe en qué perfil corre, y §2 declara
retenciones POR PERFIL. La decisión: placeholders de clase-config
POR VALOR (__OBS_RETENCION_METRICAS__, __OBS_RETENCION_LOGS__,
__OBS_CF_CAIDO_FOR__, __OBS_DEADMAN_REPEAT__), derivados de
$PROFILE por una tabla en el init y renderizados por
render_platform_placeholders — el mismo dueño único que ya
renderiza __ROOT_DOMAIN__ y verifica que ninguno sobreviva. Además
__AEGIS_PROFILE__ (el nombre) como external_label de las métricas:
identidad, no comportamiento.

POR QUÉ valores y no solo el nombre: un `perfil: hetzner` en un
YAML estático es un fork que ALGO tendría que interpretar — un if
de Helm, un overlay de kustomize — y esa maquinaria no existe en
la semilla; agregarla por esto sería rediseño (violaría la regla
de hooks.md). Los valores concretos mantienen los manifests
declarativos y el render existente alcanza: una línea más por
placeholder en el sed, cero mecanismo nuevo. El nombre viaja
además como etiqueta para que los DATOS digan de qué perfil
salieron (un dashboard puede distinguir «sin dato» de «cero»
según la semántica del perfil, §3.3). Caso borde horneado: el
perfil es identidad DE NACIMIENTO — tras el render el placeholder
está muerto y cambiar de perfil en una instancia viva es editar
valores en git, no re-correr el init. Mecánica y tabla de valores:
fase-85.md §4.

### 4.4 Dashboards

Se derivan de las preguntas de §1, como estaba previsto — ahora
con visor. Set inicial (ConfigMaps en git, sidecar): bootstrap
(gates.jsonl: duración/resultado por fase y por corrida),
plataforma (ArgoCD sync/drift, certs, cloudflared, Kyverno),
supply-chain (eventos: builds→digest→scan→firma, edad DB Trivy),
borde (Traefik RPS/códigos/latencia). Ninguno nace a click (§4.1).

### 4.5 Lo que SIGUE sin decidirse (honesto)

- El log humano por corrida del init: §2 lo lista como «archivo
  por run» pero HOY el stderr de una corrida no se captura (etapa
  C de RUTA.md; gates.jsonl SÍ existe y es lo que se ingesta).
- aegis-chequeo como métrica pusheada al store: entra cuando B6
  esté verde, no antes (nota en RUTA.md pista B).
- node-exporter / kube-state-metrics: DIFERIDOS a propósito. El
  cAdvisor del kubelet ya da CPU/mem por contenedor vía scrape con
  el ServiceAccount de vmagent; el disco del HOST queda sin
  métrica hasta que duela — anotado, no olvidado (I4: cada
  componente nuevo se gana su lugar).
