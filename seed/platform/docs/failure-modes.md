# failure-modes.md — clases de fallo de aegis, firmas y fixes

Fuente: 14 corridas de validación greenfield (2026-07) + reporte de
ingeniería del agente in-VM (post-#14). Los comentarios "corrida #N /
H-N / CR-N / A-N" dispersos en el código son el logbook embebido;
ESTE archivo es el índice por CLASE — para humanos y para agentes AI
que necesiten contexto recuperable sin leer 2.400 líneas de lib.

Regla de la casa: cuando el mismo tipo de bug aparece 2+ veces, se
ataca la CLASE (helper + check estático con dientes probados), no el
síntoma. Las cuatro enfermedades de abajo nacieron así.

---

## Enfermedad A — "YAML como string" (templating por texto)

Instancias: H4 (#13, guards `grep -q` matcheaban comentarios — 4
sitios), CR-0/CR-1/CR-2 (#14, inyecciones replace()/next() escribían
en comentarios o con el indent equivocado), H6 (#13, variante:
material montado donde el consumidor no lo lee).

Firmas típicas (aparecen ESLABONES DESPUÉS de la causa):
- kustomize: `missing Resource metadata` / `accumulating resources`
- helm: `did not find expected key`
- ArgoCD: ComparisonError permanente en una App que "debería" estar
- recurso huérfano sin error: entry jamás agregada, Secret NotFound

Fix de clase (vigente):
- LECTURA de estructura: `yaml_lists_file` (solo la ENTRY de lista
  cuenta, nunca el comentario) — común.sh, check 41.
- ESCRITURA de estructura: `inject_placeholder` — no-comentario,
  ocurrencia única, indent de la línea real, YAML validado ANTES de
  escribir (destino intacto si no parsea) + `placeholder_pending`
  para el re-run — common.sh, check 48, harness con las formas
  exactas de CR-1/CR-2.
- Detección temprana (Patrón A-2c): build del directorio afectado
  inmediatamente después de la edición (`kubectl kustomize` del dir
  de policies en la 80; `kubectl apply --dry-run=server` del CR en
  la 70 — el dir KSOPS no se buildea local). Checks 43/56.
- Defensa doble: los comentarios de platform/ NO escriben
  placeholders literales (check 48c).

Decisión sobre ruamel.yaml (opción 1 del reporte): NO por ahora.
Sería el fix definitivo (asignar al path y serializar), pero agrega
una dependencia python no-stdlib al host del init por un margen que
inject_placeholder + validación + checks ya cubren; se reevalúa si
la clase vuelve a morder A PESAR del helper. Registrado como
decisión, no como olvido.

## Enfermedad B — gates que no aíslan la propiedad que verifican

Instancias: CR-3 (#14, scope-probe sin limits → lo rechazó la quota
ANTES de Kyverno → gate rojo por la razón equivocada), CR-4 (#14, el
negativo aceptaba CUALQUIER fallo → PSS/quota podían dar falso verde
en EL gate de la plataforma).

Regla adoptada (todo gate de admisión):
1. El probe cumple TODAS las demás políticas del namespace (PSS,
   quota) — lo único no-compliant es la propiedad bajo test.
2. El assert va sobre el MENSAJE del deny (debe citar
   `require-aegis-signature`), no sobre el exit code.
3. Al fallar, el gate imprime la evidencia que distingue causas
   (gate_diag: events/describe/operationState/console — H7 #13).
Checks 47/50.

## Enfermedad C — consistencia eventual tratada como síncrona

Instancias: carrera lastBuild (#9), argo_sync con App ya-Healthy
(#8), CR-2-poll (#14: restart 2s post-policy-ready cuando el deploy
aún apuntaba al tag PRE-firma).

Regla: tras cada transición de estado, el paso siguiente hace poll
de la PRECONDICIÓN que necesita, nunca del tiempo transcurrido.
Ejemplos vigentes: argo_sync espera la fase TERMINAL de la operación
NUEVA (startedAt); los builds se esperan por NÚMERO capturado ANTES
del disparo; el positivo de la 80 espera `@sha256:` en el deploy
ANTES del restart (check 51).

PROPIEDAD OPERATIVA (no detalle): Kyverno NO re-muta UPDATEs sin
cambio de imagen — un Deployment admitido PRE-policy que referencia
un tag queda irreiniciable (deny determinista en el ReplicaSet)
hasta el próximo bump de imagen. Cualquier runbook de "rollout
restart" en org-personal debe considerar esto.

## Enfermedad D — estado dual git (clone local vs remoto)

Instancia: CR-6 (#14, fix manual del operador en GitHub durante un
retome → el clone del init quedó detrás → riesgo de pisar/chocar).

Fix: `platform_repo_sync` (common.sh) al abrir CADA fase que muta el
repo de plataforma (25/40/50/70/80): fetch + merge --ff-only; si
divergió, muere con el estado visible — el init nunca decide solo un
merge. Check 52.

---

## Transitorios de red / entorno (E-1)

El entorno dev es intermitente POR DISEÑO (red móvil del operador) y
el DNS de la VM se ensucia. Dónde vive la tolerancia:
- `retry_net` en todo egress puntual (git, curl, gh).
- `argo_secrets_gate` clasifica ComparisonError: firma de red
  (dial tcp / i/o timeout / lookup / EOF / connection re*) = espera;
  kustomize roto = fatal inmediato.
- A los 60s de transitorio sostenido se imprime el runbook DNS
  (§1.9 de VALIDACION) como PISTA. La remediación (restart de
  CoreDNS) la decide el operador — el init no reinicia componentes
  del cluster por su cuenta.

## Riesgos aceptados (decisiones con costo, no bugs)

- **Single-node / fail-closed**: crash duro de Kyverno congela
  org-personal. Deliberado (A44, blast radius acotado). Pre-Hetzner:
  réplicas 2-3 del admission controller + PodDisruptionBudget (el
  values ya lo anota).
- **Bash como orquestador (~2.400 líneas de lib)**: bien mientras
  las primitivas (gate/poll/inyección/store) estén extraídas en libs
  con harness — que es el estado actual. Regla: no crecer sin
  harness de la primitiva nueva; migrar de lenguaje NO urge.
- **ClusterIP fija del registry en los caminos del INIT** (curl,
  cosign verify): el cert tiene la IP en SANs y funciona; los
  manifests ya usan el NOMBRE. Desde H2 (#13) el host resuelve el
  nombre vía /etc/hosts, así que unificar init→nombre es posible —
  DIFERIDO deliberadamente a post-#15 para no tocar un camino
  validado antes de la corrida hands-off (registrado en VALIDACION
  §5). Un cambio de CIDR hoy rompe en ~4 lugares a la vez: ese es el
  costo aceptado.
- **tlog/SCT apagados** (rekor.ignoreTlog + ctlog.ignoreSCT +
  --tlog-upload=false): correcto para firma offline sin Sigstore
  SaaS; significa CERO transparencia de firmas. Si aegis apunta a
  producción multi-tenant: reevaluar Rekor self-hosted (trigger: el
  mismo de la lista de rotación — primer cliente con SLA).
- **Deuda #103**: background:false en la policy (drift detection
  apagada). Rastreable en el backlog; el CA global ya lo permitiría.

## Trazabilidad diseño ↔ código (D-1)

Regla post-#14: todo criterio de éxito del diseño tiene (a) su
assert en código, o (b) un registro explícito de "no implementado +
por qué". El caso que la parió: "cerrar issue #56" — aclarado en
VALIDACION.md (task del backlog interno de la sesión, cierre MANUAL
del operador; el init no cierra nada).

## Diagnóstico de corridas para agentes (P2.13)

Cada gate apendea JSON a `init/.init-state/gates.jsonl`
(`{ts, phase, gate, result, duration_s}`) — una corrida histórica se
diagnostica con jq, sin parsear el log ANSI:

    jq -r 'select(.result=="fail") | "\(.phase) \(.gate) \(.duration_s)s"' \
        init/.init-state/gates.jsonl
