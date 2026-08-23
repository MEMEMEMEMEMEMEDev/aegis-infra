# AGENTS.md — contrato para trabajar sobre este artefacto

Este archivo es para el agente (AI o humano) que va a MODIFICAR
aegis-v2: agregar features, arreglar bugs, atacar ítems del backlog.
Leelo entero antes de tocar nada — casi todas las reglas de acá
nacieron de un incidente real que costó una corrida.

Si en cambio estás en la VM donde la plataforma CORRE → `OPERAR.md`.
Si querés entender el porqué histórico de todo → `HISTORIA.md`.

---

## 1. Qué es esto y en qué estado está

aegis-v2 es el bootstrap declarativo de la plataforma aegis:
`init/` (orquestador de 14 fases idempotentes) + `platform/` (el
repo de plataforma que el init despliega: tofu Cloudflare-only,
ansible, manifests K8s App-of-Apps, ci-images, docs).

Estado: **VERSIÓN 2 CERRADA (2026-07-24)** — validada de punta a
punta contra VM real: 14/14 fases, 146+ gates en verde incluidos los
fail-closed, tenant aislado (netpols, RBAC, build sin privilegios,
firma + admisión Enforce), y tools de recuperación (backup/restore/
rotate/destroy) ejercitados. `main` es la rama de verdad.

La secuencia canónica de fases y las decisiones D1-D11 están en
`platform/docs/architecture/bootstrap.md`. **Si ese doc y el init
divergen, es un bug: se corrigen juntos en el mismo commit.**

## 2. Los dos mundos: dónde estás parado

- **WSL (la máquina del operador)** — acá vive EL repo
  (`~/aegis-v2`, git, remoto privado). Acá se edita, se corre
  `verify-static.sh`, se commitea. Es la máquina PRIMARIA del
  operador: cuidado extremo con comandos destructivos (`rm -rf`
  está efectivamente prohibido fuera de scratch).
- **La VM (VirtualBox, desechable)** — acá se CORRE el init
  (`~/workspace/aegis-v2`, un clone). Cada corrida arranca de
  snapshot limpio. La VM se rompe y se revierte sin drama; el repo
  en WSL jamás.

El planning (backlog W-NN, roadmap de olas, paquetes de corrida,
evidencia) vive en un workspace separado del operador, fuera de este
repo. Pedíselo si lo necesitás.

## 3. El método (no negociable)

Todo cambio sigue este ciclo, sin saltos:

```
1. UN ítem = UN commit (Conventional Commits).
2. El fix ataca la CLASE, no el síntoma (si el mismo tipo de bug
   aparece 2 veces → helper canónico en init/lib/).
3. Todo fix/feature lleva su check en init/verify-static.sh.
4. Todo check se valida con su DIENTE: mutás el código (rompés lo
   que el check protege) y verificás que el check FALLE. Un check
   que no muerde no existe.
5. verify-static.sh: TODO PASS antes de commitear.
6. Nada está "hecho" hasta que una CORRIDA lo valida en la VM.
   La corrida la lanza el operador; vos preparás el paquete (qué
   vigilar, qué gates nuevos, cómo diagnosticar si frena).
```

Sobre los dientes: mutaciones débiles producen falsa confianza. La
mutación correcta es la regresión REAL (el bug que motivó el check),
no un cambio cosmético. Está documentado que dientes bien hechos
cazaron bugs en los propios checks.

Sobre las corridas: el criterio vigente es UNA pasada desde snapshot
limpio, cero intervenciones manuales, exit 0, `gates.jsonl`
archivado como evidencia. `--from <fase>` se permite solo durante
debugging iterativo, nunca como validación final.

## 4. Reglas duras (cada una tiene un cadáver detrás)

### Secretos

- NUNCA imprimir contenido de Secrets: ni `kubectl get secret -o
  yaml/json`, ni `--decode`, ni base64. Shape-checks solo por
  longitud (`wc -c` sobre archivo).
- Secretos JAMÁS en argv (`/proc/PID/cmdline` es público):
  `--from-file`, stdin, `htpasswd -i`, `jq --rawfile`.
- SOPS cifra EN la ruta del repo (la creation_rule matchea por
  path): `mv` primero, `sops -e` después, roundtrip SIEMPRE
  (`sops -d | head -c1`).
- Material en claro solo en tmpfs (`/dev/shm`), chmod 700, shred al
  salir.
- Secrets K8s por `data:` byte-preserving; NUNCA `stringData`
  armado a mano (el folding YAML agrega 1 byte y rompe HMACs).
- Credenciales compartidas (htpasswd↔regcred, HMAC↔webhook): UN
  origen, derivación en el MISMO proceso, UN commit.
- La age key es EL irreducible: jamás en un backup bundle, jamás en
  un log, jamás en el repo. Todo lo demás se recupera con ella.
- La docena completa: `platform/docs/conventions/secrets.md`.

### Verificación

- **El binario decide, la doc es una hipótesis.** Versiones, flags,
  schemas de CRD: verificar contra lo desplegado (`kubectl explain`,
  `--dry-run=server`, tags reales del registry remoto), nunca desde
  memoria de entrenamiento. Este proyecto tiene 7 instancias
  documentadas de "la doc mintió" y al menos 2 de "el pin inventado
  de memoria no existía".
- No afirmar "está hecho" sin verificar en la fuente. Roadmap ≠
  estado.
- El test definitorio es el del CONSUMIDOR real (cliente→servidor
  real), no una lectura local que lo proxee.
- Traer recursos byte-idénticos a los que funcionaron en vivo, no
  reconstruirlos de memoria.

### Código del init

- stdout SAGRADO: todo log a stderr. Cualquier función cuyo valor
  se capture con `$()` no puede loguear a stdout (mordió 2 veces).
- Nunca `if (source fase)` ni condiciones que envuelvan código con
  `set -e` — bash ignora errexit en contexto de condición (estuvo
  muerto 15 corridas). Patrón: `set +e; (source); rc=$?; set -e`.
- YAML nunca por texto: leer estructura con `yaml_lists_file`,
  escribir con `inject_placeholder` (valida el YAML antes de
  escribir). Los guards `grep -q` sobre YAML están prohibidos
  (check 41) — matchean comentarios.
- Convergencia antes de medir: EXISTENCIA → ESTABILIDAD → MEDIR
  (`wait_for` / `k8s_converged` / `deploy_current_pods_ok`).
  Prohibido `items[0]` sobre colecciones en cascada (check 72).
- Transitorio ≠ fallo: "no convergió" espera con timeout generoso;
  "convergió a error" corta con diagnóstico. Firmas de red
  centralizadas en `AEGIS_NET_SIGS`.
- Todo gate: puede fallar, aísla la propiedad que verifica (el
  probe cumple TODAS las demás políticas del namespace), asserta el
  MENSAJE del rechazo, habla al fallar (`gate_diag`) y registra en
  `gates.jsonl`.
- Pasos de revert NUNCA con `&&` — cada paso con su exit code
  visible.
- tofu SIEMPRE vía el wrapper (`platform/tofu/tofu-apply.sh`) — a
  pelo faltan las TF_VARs y hay destroys fantasma de recursos
  count-gated.
- Del lado del host: python3+pyyaml (yq NO está instalado en WSL).

### Git y repos

- Los repos sobre los que el init escribe son DESECHABLES (topic
  `aegis-v2-disposable`). Sin marcador → ABORTA. Jamás operar
  contra repos reales del operador.
- Workflow: feature branch → PR/merge a main. Merges de integración
  con `--no-ff`. Nunca commitear directo a main sin acuerdo.
- Nunca borrar/forzar sobre algo que no creaste sin mirar primero
  qué hay.

## 5. Autonomía: cuándo frenar

Clasificá cada acción ANTES de ejecutarla:

- **VERDE (fluí)**: leer, buscar, editar código + check + diente,
  correr verify-static, commitear en branch propia.
- **AMARILLO (un freno: mostrá y esperá OK)**: merge a main, push,
  cambios de diseño no discutidos, tocar caminos ya validados por
  corrida, cualquier cosa en la VM que mute estado del cluster.
- **ROJO (parar y preguntar)**: todo lo irreversible (destroy real,
  rotación de irreducibles, borrar recursos externos — webhooks,
  DNS, repos), todo lo que toque secretos en claro, y todo
  diagnóstico donde tu hipótesis contradiga la evidencia del
  operador (pasó 2 veces; el operador tenía razón las 2).

Regla de diagnóstico: ante un síntoma con múltiples causas
conocidas (ej. "webhook 400" tiene DOS), discriminar con evidencia
ANTES de tocar nada. Borrar un recurso por hipótesis errada costó
una corrida entera.

## 6. Cómo correr las herramientas

```bash
# La suite estática (desde la raíz del repo, en WSL):
./init/verify-static.sh              # 83 checks; exit 0 = PASS
./init/verify-static.sh --with-charts  # + renderiza los charts reales

# exit 3 = CHECK INESTABLE (bug del verificador, no del artefacto)

# El init (SOLO en la VM, jamás en WSL):
./init/aegis-init.sh --check                 # dry-run
./init/aegis-init.sh --profile greenfield    # corrida completa
./init/aegis-init.sh --from 50-jenkins       # retome (re-ejecuta la fase)
AEGIS_VALIDATE_FAILCLOSED=1 ...              # habilita gates disruptivos

# Tools out-of-band (VM):
init/aegis-backup.sh        # bundle age-cifrado + ROUNDTRIP verificado
init/aegis-restore.sh       # inverso; --force para pisar
init/aegis-rotate.sh        # DRY-RUN default; --yes invalida del store
init/aegis-destroy.sh       # DRY-RUN default; --yes destruye CF + purga
```

Diagnóstico de una corrida histórica sin parsear logs ANSI:

```bash
jq -r 'select(.result=="fail") | "\(.phase) \(.gate) \(.duration_s)s"' \
    init/.init-state/gates.jsonl
```

## 7. Estructura de un cambio típico (ejemplo real)

El commit `a068a1c` (fix del race de kube-router) es el molde:

1. Bug real en corrida: gate `trivy-responde` exit 7 con netpol
   correcto y servicio sano.
2. Diagnóstico en vivo con evidencia (exec-curl OK, pod fresco
   falla 5/5 → el CNI tarda en programar el ipset).
3. Fix de clase: retry DENTRO del pod (no fuera — un pod nuevo por
   intento re-entra al race).
4. Check estático: el probe de la fase 80 debe reintentar
   intra-pod (check 79, con awk sobre el bloque real del gate).
5. Diente: `sed 's/for i in 1 2 3/WHILE_NADA/'` → el check falla →
   el diente muerde.
6. Un commit, mensaje con el porqué, referencia a la corrida.

## 8. Orden de lectura recomendado para arrancar

1. Este archivo (ya estás acá).
2. `platform/docs/architecture/bootstrap.md` — la secuencia y sus
   porqués.
3. `platform/docs/conventions/secrets.md` — las reglas duras.
4. `platform/docs/failure-modes.md` — las clases de fallo y sus
   firmas.
5. `HISTORIA.md` — el proceso completo si necesitás contexto
   profundo.
6. El código: `init/aegis-init.sh` → `init/lib/common.sh` → la fase
   que vayas a tocar → los checks que la cubren en
   `init/verify-static.sh` (buscá el número de fase o el nombre del
   gate).

---

*Última actualización: 2026-07-24, al cierre de VERSIÓN 2.*
