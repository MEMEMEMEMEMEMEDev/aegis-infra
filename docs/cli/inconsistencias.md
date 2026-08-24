# REGISTRO DE INCONSISTENCIAS — el renombrado de la superficie CLI

**Levantado el 2026-08-21**, por cuatro auditorías paralelas, ANTES de tocar
una sola línea. Es un inventario, no un plan: el plan vive en `cli/design.md`
cuando exista.

## La regla

**Nada se renombra si no está en esta lista.** Y al revés, que es lo que
importa: **si algo no está en la lista, no es que esté bien — es que nadie lo
miró.** El registro se tacha entero o el renombrado no está hecho.

## El alcance acordado

Se renombra: nombres de comando, subcomandos, flags, y todo texto que imprime
un `--help`.

NO se toca: el vocabulario de los contratos (`organizacion:`, `usa:`,
`cuota:`), los comentarios del código, los mensajes que un comando narra
mientras corre, ni los nombres derivados en el cluster
(`shop-cabeceras`, `allow-api-a-internet`).

Ese recorte tiene una consecuencia que aparece en A3 y hay que leer con
atención: **el día que alguien traduzca los mensajes, hay una bomba armada.**

## Los números

| dimensión | cantidad |
|---|---|
| Dependencias DURAS (un comando ejecuta a otro) | 77 |
| Strings visibles al operador que nombran comandos | ~155 (48 de criticidad alta) |
| Menciones crudas totales del nombre | 452 |
| Casos de Enfermedad E confirmados | 7 (5 plenos) |
| Comandos de `platform/bin/` que algún check verifica | **1 de 12** |
| Comandos que la semilla lleva | **3 de 12** |

---

# CLASE A — ROMPE EN SILENCIO (Enfermedad E)

Lo más grave del registro. En todos estos casos el renombrado **no produce un
error**: produce un verde o un amarillo que se lee como estado normal.

El patrón que los genera es siempre el mismo: **el código de "el archivo no
está" (127, rc 2, `False`) colisiona con un código que ya estaba reservado
para una degradación legítima y esperada.**

### A1 · `aegis-chequeo` deja de medir el borde y los webhooks, y dice "sin fallos"

- **Dónde**: `platform/bin/aegis-chequeo:635` y `:654`
- **Qué pasa**: invoca `aegis-borde` y `aegis-webhook` por ruta relativa, sin
  guarda de existencia. Corre con `set -uo pipefail` **sin errexit**, así que
  un binario ausente devuelve 127, y el `case $?` no tiene rama para 127: cae
  en `*)` → `avisos++`. `fallos` nunca sube → el veredicto final imprime
  **`sin fallos, N aviso(s)` y sale 0.**
- **Qué se pierde**: la sección que compara los hostnames declarados contra
  los que existen de verdad en Cloudflare, y la que verifica que un push
  llegue a Jenkins. El 2026-08-05 esa segunda encontró que **dos de cuatro
  repos no tenían webhook**.
- **Por qué duele**: la rama `*)` se escribió para el rc=2 honesto de
  `aegis-borde` ("no pude hablar con Cloudflare"). El renombrado inyecta un
  127 **disfrazado de rc=2**, indistinguible de la degradación esperada.
- **Arreglo**: guarda `[[ -x ... ]]` antes de invocar, o rama explícita
  `127) mal "..." ;;`.
- [ ] pendiente

### A2 · El check 4 de `verify-static` pasa exactamente igual sin medir nada

- **Dónde**: `init/verify-static.sh:165`
  (`hay_generador = (P/"bin"/"aegis-org").is_file()`)
- **Qué pasa**: si el archivo no está, `hay_generador=False` → `StopIteration`
  → `por_contrato = {}` → el check imprime **PASS idéntico**, con una línea
  informativa extra que se lee como "la semilla nace sin organizaciones".
- **Qué se pierde**: el productor 2 completo (la razón por la que el check se
  reescribió en #48), y el **único consumidor estático** de la API interna del
  generador — `gen.secretos_de`, `gen.repos_de`, `gen.orgs_con_bucket`.
- **La asimetría que lo hace venenoso**: si `aegis-org` existe pero revienta al
  importarse → `FAIL` correcto. Si **no existe** → silencio. El camino "no
  está" está tratado como legítimo, y el renombrado lo vuelve indistinguible de
  "lo movimos y nadie lo actualizó".
- **Arreglo**: derivar la ausencia del generador de la ausencia de
  `orgs/*.yaml`, no de la ausencia del archivo. Si hay contratos, el generador
  DEBE existir.
- [ ] pendiente

### A3 · Un webhook recién creado se reporta como "ya estaba" — **la bomba de la capa de mensajes**

- **Dónde**: `platform/bin/aegis-app:713`
  (`creo = escribir and "webhook creado" in r.stdout`)
- **Productor del string**: `platform/bin/aegis-webhook:182`
- **Qué pasa**: `aegis-app aplicar` decide si convergió o no **grepeando un
  literal en español** del stdout de otro comando. Si ese mensaje cambia,
  `creo=False` y la tabla marca `ya estaba` en vez de `hecho`. Sin excepción,
  sin rc distinto, sin rastro.
- **Por qué es EL caso especial de este registro**: es el único disparado por
  traducir un **mensaje**, no un nombre. Como acordamos dejar los mensajes en
  español, **hoy no se activa** — pero queda armado para el día que alguien
  toque esa capa. Es el argumento para arreglarlo ahora que estamos acá.
- **Lo dice el propio comentario** (`:710-713`), sin saber que se autodescribe:
  *"Se lee del reporte del delegado — sus estados son estables"*. El renombrado
  es exactamente el evento que rompe esa suposición.
- **Arreglo**: que `aegis-webhook` comunique el estado por rc o por una línea
  máquina-legible (`STATE=created`), nunca por prosa traducible.
- [ ] pendiente

### A4 · La rotación devuelve ÉXITO si el sincronizador no está

- **Dónde**: `init/aegis-rotate.sh:757`
- **Qué pasa**: `[[ -x "$PBIN/aegis-sync" ]] || { log_warn ...; return 0; }` —
  **`return 0` es éxito**. Rotar una credencial sin empujar el Secret nuevo
  deja el cluster con el material viejo.
- **El único rastro** es un `log_warn` que dice "sincronizá a mano", que se lee
  como instrucción de rutina y no como "el paso mecanizado desapareció".
- [ ] pendiente

### A5 · Dos verificadores se desactivan y la rotación se declara completa

- **Dónde**: `init/aegis-rotate.sh:243` y `:641`
  (`[[ -x "$PBIN/aegis-webhook" ]] || return 3`, ídem `aegis-registro`)
- **Qué pasa**: rc=3 significa "NO VERIFICABLE" y está bien documentado, pero
  el consumidor (`:1062-1065`) hace `return 0` al que llama.
- **Lo peor es el mensaje**: dice *"NO HAY DIENTE que lo verifique. Escribí el
  verificador"* — **atribuye activamente la causa equivocada**. Manda a
  escribir un verificador que ya existe, y el operador lo archiva como deuda
  conocida mientras la rotación del HMAC de Jenkins y la del registry se
  declaran hechas sin haberse verificado nunca.
- **Atenuante**: no se escribe el marcador `.done`, queda rastro en disco.
- [ ] pendiente

### A6 · El job de CI del borde queda AMARILLO permanente con diagnóstico falso

- **Dónde**: `platform/edge-chequeo/Jenkinsfile:117` (`python3 bin/aegis-borde`)
- **Qué pasa**: con el archivo ausente, `python3` sale con **rc 2** — que es
  justo el código reservado para "no se pudo evaluar". El job queda `UNSTABLE`
  con el mensaje *"falta credencial o Cloudflare no respondió"*.
- **Parcial** porque no es verde. Pero un amarillo recurrente con causa externa
  plausible es exactamente cómo un check deja de leerse.
- **La ironía**: el comentario inmediatamente arriba (`:119-122`) nombra la
  Enfermedad E como su razón de existir.
- [ ] pendiente

### A7 · El check 86 degrada en silencio si se toca `aegis-init.conf`

- **Dónde**: `init/verify-static.sh:2893-2906`
- **Qué pasa**: si el conf no está, el refuerzo que detecta valores de la
  instancia filtrados a la semilla **desaparece y el check pasa igual**, con
  un sufijo en el mensaje de PASS.
- **Condicional**: `aegis-init.conf` no está en el alcance del renombrado, pero
  está en el mismo radio de explosión que `aegis-init.sh`.
- [ ] pendiente

---

# CLASE B — CONTRATOS DE TEXTO (centinelas que se parsean)

Literales que no son mensajes: son **estructura**. Si el texto y su lector se
desincronizan, el mecanismo deja de funcionar sin avisar.

### B1 · El centinela que evita pisar ediciones manuales

- **Dónde**: `platform/bin/aegis-org:1162`
  (`if "GENERADO POR \`aegis org\`" in viejo and ...`)
- **Escrito en**: las cabeceras de `:355, 1721, 1838, 2008, 2135, 2160, 2250`
- **Qué protege**: decide si un archivo generado fue editado a mano y no debe
  pisarse. **Si la cabecera y el centinela se renombran en commits distintos,
  el guardia deja de disparar y empezamos a pisar ediciones manuales.**
- [ ] pendiente

### B2 · La marca que delimita el bloque de jobs de Jenkins

- **Dónde**: `platform/bin/aegis-org:2393`
  (`JOBS_BLOCK_START = "# --- DERIVADO por aegis-org (jobs de tenant)..."`)
- **Leída en**: `platform/k8s/base/platform/jenkins/values.yaml:102,107`
- **Qué protege**: es un contrato de texto entre el generador y un YAML
  versionado. Sin la marca, el bloque derivado se reescribe en el lugar
  equivocado o no se reescribe.
- [ ] pendiente

### B3 · El literal "Resume:" que un check valida por texto exacto

- **Dónde**: `init/aegis-init.sh:212`, validado por `init/verify-static.sh:2171`
- **Doble acople**: un nombre de archivo *dentro* de un mensaje impreso, que
  además otro archivo grepea literal.
- [ ] pendiente

---

# CLASE C — DEPENDENCIAS DURAS (77) — fallan, pero ruidosamente

Un comando ejecuta o importa a otro. Rompen de verdad; al menos gritan.

### C1 · Los seis `SourceFileLoader` — **hay que grepear DOS formas**

El módulo se carga como `aegis_org` (guion **bajo**) desde el archivo
`aegis-org` (guion **medio**). Un grep por una forma no encuentra la otra.

- `platform/bin/aegis-app:132-134`
- `platform/bin/aegis-borde:63-65`
- `platform/bin/aegis-secreto:516-518`
- `platform/bin/aegis-org-prueba:26-27`
- `platform/bin/aegis-tipos-prueba:29-30`
- `seed/platform/bin/aegis-secreto:518`
- `seed/platform/bin/aegis-tipos-prueba:30`
- [ ] pendiente

### C2 · Invocaciones armadas por tupla o variable (invisibles a un grep simple)

- `platform/bin/aegis-app:513-516` — `["aegis-org", "aplicar", ruta]` y
  `["aegis-secreto", "--todos", ruta]` como **elementos de lista**: el string
  `"bin/aegis-org aplicar"` no existe en ningún lado.
- `platform/bin/aegis-app:100,704` — `WEBHOOK = os.path.join(AQUI, "aegis-webhook")`
- `init/aegis-rotate.sh:56` — `PBIN="$PLATFORM_DIR/bin"` y luego
  `"$PBIN/aegis-webhook"`, `"$PBIN/aegis-registro"`, `"$PBIN/aegis-sync"`,
  `"$PBIN/aegis-chequeo"`. Un `grep "platform/bin/aegis"` **no los ve**.
- `platform/bin/aegis-chequeo:635,654` — `$(dirname "${BASH_SOURCE[0]}")/aegis-borde`
- [ ] pendiente

### C3 · La única llamada de una fase del init a `platform/bin/`

- **Dónde**: `init/phases/85-observability.sh:298`
  (`bin/aegis-org borde`)
- **Modo de falla**: muere en la fase 85 de una corrida real, **horas adentro
  del bootstrap**. Y el check 17 (*"archivos que las fases referencian
  EXISTEN"*) **no lo cubre**: su regex solo mira `ansible/...` e
  `$AEGIS_ROOT/init/...`.
- [ ] pendiente

### C4 · El resto de las duras

- `init/aegis-rotate.sh:751` → `aegis-init.sh --only <fase>`
- `init/aegis-rotate.sh:642` → `aegis-registro --revisar`
- `init/aegis-rotate.sh:1139` → `aegis-chequeo`
- `platform/edge-chequeo/Jenkinsfile:117` + `jenkins/values.yaml:275`
  (`scriptPath('edge-chequeo/Jenkinsfile')`)
- `init/verify-static.sh` — ~17 referencias por ruta literal y grep:
  `:397, 459-460, 969, 999, 1652, 1715-1717, 2028-2030, 2171, 2502-2517,
  2597-2620, 2628-2646, 2655-2668, 3067-3069`
- Los 19 `source "$AEGIS_HOME/aegis.conf"` (13 fases + 6 más)
- [ ] pendiente

---

# CLASE D — CONTRATOS DE NOMBRE ADYACENTES

No son la CLI, pero se rompen si el renombrado los arrastra — o si NO los
arrastra.

| # | contrato | acoplado con | riesgo |
|---|---|---|---|
| D1 | `.aegis-app/` (staging) en `platform/.gitignore:37` | `aegis-app:99` `DIR_STAGING`, y `aegis-org:55` usa el mismo | Renombrar el dir sin tocar el ignore = **commitear material generado** |
| D2 | glob `aegis-estado-*.age` | escrito por `init/aegis-backup.sh:51`, leído por `aegis-chequeo:845` | El chequeo de respaldos no encuentra nada |
| D3 | glob `aegis-datos-org-<org>-*.age` | escrito por `aegis-respaldo:518`, leído por `aegis-chequeo:883` | ídem |
| D4 | marca `.aegis-destino` | `aegis-respaldo:164` ↔ `aegis-chequeo:831` | |
| D5 | `/etc/sudoers.d/010-aegis-init-nopasswd` | `aegis-preflight.sh:31-32`, `lib/common.sh:737,739,755`, `phases/00-preflight.sh:60` | 5 lugares |
| D6 | topic de GitHub `aegis-app` | `aegis-app:106` | los repos ya creados lo llevan |
| D7 | `initiatedBy.username: "aegis-sync"` | `aegis-sync:56` | **queda grabado en el historial de ArgoCD**; decidir aparte |
| D8 | `aegis-preflight.sh` se autocopia a `$HOME` con nombre hardcodeado | `:169` y `:175` | |
| D9 | La regla `("bin/aegis-org-prueba", ...)` en `bin/aegis-semilla:129` | `:252-256` `morir()` si no matchea | **Mata los tres subcomandos de `aegis-semilla`.** Único fallo ruidoso del renombrado — y es un falso positivo |

- [ ] pendiente

---

# CLASE E — STRINGS AL OPERADOR (~155, de los cuales 48 críticos)

No rompen nada. **Solo guían mal**, que en esta casa es peor.

Los 10 donde un usuario nuevo queda sin siguiente movimiento:

1. `init/aegis-init.sh:212` — `"Resume: ... --profile ... --from ..."`. Única
   salida tras una fase fallida del bootstrap. (Y ver B3.)
2. `platform/bin/aegis-app:573-578` — el bloque **"siguientes pasos, EN ORDEN"**.
   Es el handoff completo del alta de una organización.
3. `platform/bin/aegis-org:1200` — `"se crean con: bin/aegis-secreto --todos"`.
   El comentario del código dice *"El comando exacto, no 'creá los secretos'"*.
4. `init/aegis-rotate.sh:1196-1199` — cierre de una rotación. Sin esto la
   plataforma queda a medio sincronizar.
5. `init/aegis-rotate.sh:717,722` — lo mismo, pero mid-tanda: el estado más
   frágil del sistema.
6. `platform/bin/aegis-app:295` — diagnóstico + remedio en un solo string.
7. `lib/config.sh:184` — bloquea toda corrida desatendida.
8. `platform/bin/aegis-sync:31-32,59` — tres en un archivo de 59 líneas.
   `aegis-sync` es el comando más citado por otros comandos.
9. `seed/platform/orgs/README.md:11-14` — **el README que se siembra en
   cada instancia nueva**. Cuatro comandos consecutivos que mueren juntos.
10. `platform/bin/aegis-app:371` y `:556-557` — las dos paredes de entrada al
    comando de alta.

- [ ] pendiente (inventario completo en las auditorías; 24 archivos)

---

# CLASE F — LA SEED

### F1 · Solo lleva 3 de los 12 comandos

`seed/platform/bin/` tiene `aegis-org`, `aegis-secreto`,
`aegis-tipos-prueba`. **Faltan los otros 9.**

### F2 · Su `aegis-org` está atrasado y diverge en contenido real

124.690 B (vivo, 2026-08-21) contra 105.042 B (semilla, 2026-08-11) —
**444 líneas de diff**. Le falta `USOS = {..., "internet"}`, todo el bloque de
derivación de jobs de Jenkins (`JOBS_BLOCK_START`), las cabeceras CSP, y la
validación de `prompt` por clase. **No es des-renderizado: es atraso.**

### F3 · `init/` no forma parte del árbol comparado

No existe `semilla/init/`. `aegis-semilla` solo compara `platform/` ↔
`seed/platform/`. **Un renombrado en `init/` no lo detecta nadie por esta
vía** — y encima `verify-static.sh` mide la SEED, no la instancia.

### F4 · El fallo aparece en otra máquina, no acá

`seed/platform/bin/aegis-tipos-prueba:30` carga `aegis-org` por nombre. Si
los dos árboles se desincronizan, la prueba del artefacto entregado revienta en
**el bootstrap de una instancia nueva**, no en el commit que lo causó. Es
exactamente el modo de fallo que `aegis-semilla` existe para evitar.

- [ ] pendiente

---

# CLASE G — DOCUMENTACIÓN QUE SE EJECUTA

Solo la de OPERADOR es peligrosa (alguien la sigue paso a paso):

| archivo | bloques | nota |
|---|---|---|
| `OPERAR.md` | 16 | **El manual de guardia. El más peligroso del repo.** |
| `docs/protocols/organization.md` ×2 | 28 c/u | Copias byte-idénticas: doble mantenimiento |
| `docs/protocols/rotation-checklist.md` ×2 | 2 | Se sigue ítem por ítem |
| `docs/protocols/rotate-age-key.md` ×2 | 34 | Ceremonia ejecutada literal |
| `docs/protocols/edge.md` | 8 | Solo en `platform/`, no viaja a la semilla |
| `seed/templates/base/README.md` | 0 (7 menciones) | Lo lee quien crea una app |
| `seed/platform/orgs/README.md` | 4 | Ver E9 |
| `caminos/design.md` | 0 (24 menciones) | **Es la fuente de verdad del diseño de la CLI** — renombrar sin tocarlo deja el diseño mintiendo |
| `AGENTS.md` | 6 | Instrucciones que un agente ejecuta |

Bitácoras (`RUTA.md` 31 menciones, `PROGRESO.md`, `VALIDACION.md`,
`HISTORIA.md`): **no se tocan.** Son registro histórico.

- [ ] pendiente

---

# CLASE H — YA ESTÁ ROTO HOY (hallazgos, no consecuencias)

Esto lo encontró la auditoría y **existe antes del renombrado**. Vale
arreglarlo de paso.

| # | qué | dónde |
|---|---|---|
| H1 | `aegis-rotate.sh` se anuncia como **`aegis-rotar`**, un nombre que no existe | `init/aegis-rotate.sh:1094` |
| H2 | Los `.tf` citan `aegis-rotate --verificar`, **sin el `.sh`** | `tofu/modules/cloudflare-access/main.tf:29,30,43`, `grafana.tf:16`, `envs/cloudflare-tunnel/variables.tf:106` |
| H3 | La doc documenta **`aegis org rotar <org> <secreto>`**, subcomando inexistente | `docs/protocols/organization.md:342` |
| H4 | **35 archivos generados llevan `aegis org` (forma despachador, que no existe) Y `bin/aegis-org` en el mismo archivo** | banners de `k8s/organizations/*/`, `k8s/argocd-apps/tenants.yaml`, etc. |
| H5 | Tres convenciones de banner vivas a la vez | las 35 de H4 + `k8s/base/ai-system/{ruteo,registro,kustomization}.yaml` en minúsculas |
| H6 | **Las dos pruebas de aceptación son huérfanas**: nadie las corre, `verify-static` no las invoca, no hay CI (`.github/` no existe) | `aegis-org-prueba`, `aegis-tipos-prueba` |
| H7 | El check 15(a) se auto-matchea con `'Bitwarden'` si se renombra `verify-static.sh` (la `--exclude` deja de morder y `:439` es la única ocurrencia del patrón en el árbol) | `init/verify-static.sh:441` |

- [ ] pendiente

---

# COBERTURA AUSENTE — lo que nada verifica

Esto no es una inconsistencia: es el hueco por donde entran todas las demás.

1. **Ningún check verifica la existencia de 11 de los 12 comandos de
   `platform/bin/`.** La única referencia en los 91 checks es el check 4 →
   `aegis-org`, y ese check ES el caso A2. **Mover los otros 11 al despachador
   es invisible: la suite sale `TODO PASS`.**
2. `verify-static.sh` apunta a `seed/platform`, no a `platform/`.
3. El check 17 no alcanza `bin/aegis-org borde` de la fase 85 (ver C3).
4. No hay CI: `.github/` no existe. Nada corre solo.

**Contrapartida obligatoria del renombrado**: un check nuevo que exija que cada
comando declarado exista, sea ejecutable y declare su `summary` y su `group`.
Sin eso, el despachador agrega una capa más donde algo puede faltar en
silencio.

---

# MAPA DE LA MEZCLA DE IDIOMAS (referencia, no acción)

El repo **ya es bilingüe** y nadie lo había mapeado. El corte es casi limpio
por árbol: **`init/` tiende al inglés, `platform/bin/` al español**, con
`aegis-rotate.sh` y `aegis-app` como las excepciones que rompen la regla.

### Los diez conflictos mismo-concepto-dos-idiomas

1. **"check" tiene cuatro formas**: `aegis-chequeo`, `--check`, `--revisar`,
   `--verificar`, más `verify-static.sh` y `edge-chequeo/`. Y
   `aegis-rotate.sh` usa `--revisar` **y** `--verificar` en el mismo script
   para dos cosas distintas que en inglés serían ambas *check*.
2. **"edge" vs "borde"**: `edge.yaml` (EN) es leído por `bin/aegis-borde` (ES);
   namespace `infra-edge` (EN), dashboard `borde.yaml` (ES),
   `docs/protocols/edge.md` (EN), y `platform/edge-chequeo/` que es
   **inglés-guion-español en un solo identificador**.
3. **"backup" vs "respaldo"**: `init/aegis-backup.sh` (EN) **invoca**
   `bin/aegis-respaldo` (ES). `OPERAR.md:269` los explica juntos.
4. **"rotate" vs "rotar"**: `aegis-rotate.sh` (EN) con flags `--rotar`,
   `--revisar`, `--verificar`, `--continuar` (ES). El caso más chirriante.
5. **"canary" vs "canary"**: `seed/canary/` (ES) genera
   `org-canary` (EN).
6. **"template" vs "plantilla"**: `seed/templates/` (ES) vs
   `docs/protocols/templates/` (EN); flag `--plantilla` (ES).
7. **"tenant" vs "organización"**: el mismo objeto según la capa —
   `orgs/`/`org-shop` vs `aegis-tenant-shop`/`aegis-tenants` vs
   `aegis-organizaciones`. Y `allow-tenants-a-gateway` es
   **inglés-español-inglés dentro de un solo nombre de recurso**.
8. **`platform/` (EN) y `seed/platform/` (ES) son el mismo árbol.**
9. **"routing"**: todo `ruteo` (ES) genera objetos `IngressRoute` (EN).
10. **`ai stop` y `ai cerrar` son alias del mismo comando en dos idiomas.**

### Archivos hermanos en dos idiomas

- Los tres contratos maestros: `edge.yaml` (EN), `plans.yaml` (ES),
  `services.yaml` (ES).
- Los cuatro dashboards: `bootstrap.yaml` + `supply-chain.yaml` (EN) junto a
  `borde.yaml` + `plataforma.yaml` (ES).
- Las catorce fases del init: todas EN salvo `85-observability.sh` y
  `15-terceros.sh`.
- Los cuatro contratos de organización: `blog`/`shop` (EN),
  `ejemplo`/`portafolio` (ES).
- Tres engines: `engine-cpu`, `engine-llm` (EN), `engine-charla` (ES).

### Nombres de comando

**12 inglés** · **6 español** (`aegis-borde`, `aegis-chequeo`,
`aegis-registro`, `aegis-respaldo`, `aegis-secreto`, `aegis-semilla`) ·
**2 híbridos** (`aegis-org-prueba`, `aegis-tipos-prueba`).

Nota curiosa: **`registro` significa dos conceptos distintos en el repo**
(`aegis-registro` = registry de imágenes; `ai-system/registro.yaml` = catálogo
de tareas de AI), y ninguno coincide con su namespace, que es
`registry-system`.

### Flags

- **Inglés**: `--check`, `--force`, `--help`, `--yes`, `--only`, `--from`,
  `--list`, `--org`, `--profile`, `--configure`, `--non-interactive`,
  `--reset-state`, `--purge-secrets`, `--stdin`, `--with-charts`
- **Español**: `--todos`, `--rotar`, `--revisar`, `--verificar`, `--continuar`,
  `--capturar`, `--listar`, `--restaurar`, `--reubicar`, `--aplicar`,
  `--plantilla`, `--hasta`, `--fuera-de-linea`, `--a`

`aegis-app` tiene `--plantilla` (ES) y `--check` (EN) **en el mismo comando**.
`ai` tiene `--force` (EN) y `--hasta` (ES) en el mismo `case`.

---

## Orden sugerido de ataque

1. **Clase A primero, ANTES de renombrar nada.** Arreglar los siete casos de
   Enfermedad E convierte el renombrado en una operación ruidosa: cualquier
   cosa que rompamos va a gritar. Hacerlo al revés es renombrar a ciegas.
2. **La cobertura ausente**, en el mismo movimiento: el check que exige que
   cada comando exista y se declare.
3. Clase B (los centinelas) — cabecera y lector en el **mismo commit**.
4. Clase C y D — el renombrado propiamente dicho.
5. Clase E y G — strings y documentación de operador.
6. Clase F — la semilla, que además arrastra la deuda F2 que ya existía.
7. Clase H — de paso, porque ya está roto.
