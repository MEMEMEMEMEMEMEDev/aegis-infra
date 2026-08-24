# DISEÑO DE LA CLI — el despachador y la superficie en inglés

**Acordado el 2026-08-21.** Este documento dice **qué debería ser**;
`cli/inconsistencias.md` dice **qué está mal hoy**. Los dos se leen juntos.

## Cuándo

**No ahora.** Se ejecuta durante la reconstrucción: semilla nueva, instancia
actual borrada, aegis levantado de cero. La razón es de economía, no de gusto:
refactorizar en vivo son 77 dependencias movidas con pinzas mientras la
instancia sigue funcionando; escribirlo bien de entrada es escribirlo bien de
entrada.

Consecuencia práctica: **`cli/inconsistencias.md` cambia de género.** Deja de
ser una lista de cirugías y pasa a ser el pliego de condiciones del código
nuevo. Los siete casos de Enfermedad E no son tareas: son reglas de diseño.

## Alcance

Se traduce **la superficie**: nombres de comando, subcomandos, flags, y todo
texto que imprime un `--help`.

Se quedan como están: el vocabulario de los contratos, los comentarios del
código, los mensajes que un comando narra mientras corre, y los nombres
derivados en el cluster.

**El corte va en el `--help`.** No podés tener un subcomando `new` que se
explique en español. Pero `listo — quedó escrito, nada tocó el mundo` sigue en
español, y está bien: los comentarios son el mejor activo del repo y
traducirlos es mucho esfuerzo, riesgo de aplanar la prosa, y casi ningún efecto
sobre quien todavía no se quedó.

Mezclar idiomas **dentro** de una capa es feo. **Entre** capas es normal.
Completar una capa antes de empezar la siguiente.

---

## 1 · El despachador

`aegis <comando> <subcomando> [opciones]`, con el mecanismo de git: **`aegis
foo` busca un ejecutable llamado `aegis-foo` y lo ejecuta.**

```
aegis app new shop
  └─► el despachador ve "app", busca aegis-app en su libexec
      └─► exec aegis-app new shop          (el comando ni se entera)
```

Por qué este y no un monolito con un `case` gigante:

- **Agregar un comando es dejar un archivo.** No hay registro que actualizar,
  ni lista de imports donde olvidarse.
- Cada comando sigue siendo ejecutable por sí solo — los scripts que ya los
  invocan directo no necesitan pasar por el despachador.
- **Los archivos ya se llaman `aegis-*`**: la convención está implementada por
  accidente desde el día uno.

### El nombre vive en un solo lugar

El despachador toma su propio nombre de `argv[0]`. Si algún día el producto no
se llama aegis, **renombrar el binario renombra la CLI entera** y no hay que
tocar veinte archivos. Es la razón técnica de que esta capa valga la pena
aunque el nombre cambie.

### Instalación

Una fase del init deja el despachador en el PATH (hoy el init instala `kubectl`
y `cosign` en `/usr/local/bin` pero **no instala sus propios comandos** — hay
que saber a qué carpeta ir y correr `bin/aegis-app`). Con un entrypoint único y
subcomandos declarados, el autocompletado de shell sale casi gratis.

---

## 2 · La ayuda se DERIVA

Es la doctrina de la casa aplicada a la CLI: **nadie mantiene el menú.**

Cada comando declara dos líneas de metadata en su cabecera:

```bash
# aegis-summary: Provision an organization from its contract
# aegis-group:   apps
```

`aegis` sin argumentos lee esas líneas de los ~20 archivos y arma el menú
agrupado. Un comando nuevo aparece en la ayuda **por existir**, igual que una
organización aparece en el cluster por tener contrato.

### El diente

`verify-static` exige que todo `aegis-*` declare `summary` y `group`, exista y
sea ejecutable. **La documentación que se desactualiza deja de ser un descuido
y pasa a ser un test rojo.**

Esto no es un adorno: hoy **de los 12 comandos de `platform/bin/` un solo
comando tiene algún check que verifique su existencia**, y ese check es el caso
A2 del registro. Sin este diente, el despachador agrega una capa más donde algo
puede faltar en silencio.

### Anatomía de un `--help` que sirve

1. **Usage** con la gramática estándar: `aegis app new <ORG> [--template NAME]`
   — angulares obligatorio, corchetes opcional.
2. **Una línea** de qué hace.
3. **Subcomandos y opciones**, alineados.
4. **Ejemplos.** Lo más saltado y lo más usado.
5. **Códigos de salida.** Acá aegis tiene una necesidad que ninguna otra CLI
   tiene: los tres desenlaces (`hecho` / `ya estaba` / `NO SE PUDO EVALUAR`)
   mapean a `0 / 0 / 1`, y que "no pude evaluar" devuelva error **tiene que
   estar escrito** porque nadie lo adivina.
6. **Dónde vive el protocolo** que ese comando implementa.

Los comandos en python reciben 1–3 gratis de argparse. Los de bash lo escriben
a mano y por eso derivan: necesitan un helper compartido en `lib/common.sh`.

---

## 3 · La gramática

### Regla 1 — los verbos son subcomandos, no flags

El síntoma delator: **un flag obligatorio y mutuamente excluyente**
(`add_mutually_exclusive_group(required=True)`) no es una opción, es un verbo
disfrazado.

```
aegis-registro --revisar|--rotar        →  aegis registry check|rotate
aegis-respaldo --capturar|--listar|...  →  aegis data backup|list|restore
aegis-secreto  --todos|--rotar|...      →  aegis secret create|rotate|move
aegis-webhook  --aplicar                →  aegis webhook check|apply
```

No es rediseñar: es hacer bien el mismo renombrado. Escribir `--rotate` en vez
de `--rotar` cuesta lo mismo que escribir `rotate`, pero deja el defecto
horneado para siempre.

### Regla 2 — el modo "mirar sin tocar" se escribe de UNA forma

El concepto ya existe y está bien; la ortografía no. Hoy se escribe
`--check`, `plan`, `--revisar`, `--listar`, `--verificar`, `plan-borrar` — seis
grafías para la misma idea, y `aegis-rotate.sh` usa `--revisar` **y**
`--verificar` en el mismo script para dos cosas que en inglés serían ambas
*check*.

Una sola forma en toda la casa.

### Regla 3 — un concepto, un idioma, un nombre

El registro documenta diez conflictos de mismo-concepto-dos-idiomas
(`edge`/`borde`, `backup`/`respaldo`, `rotate`/`rotar`, `canary`/`canario`,
`template`/`plantilla`, `tenant`/`organización`…). El nuevo árbol no los hereda.

---

## 4 · El mapa de comandos

| Grupo | Hoy | Nuevo |
|---|---|---|
| **setup** | `aegis-preflight.sh` | `aegis preflight` |
| | `aegis-init.sh` | `aegis init` |
| | `verify-static.sh` | `aegis verify` |
| | `aegis-destroy.sh` | `aegis destroy` |
| **apps** | `aegis-app nueva\|aplicar` | `aegis app new\|apply` |
| | `aegis-org plan\|aplicar\|validar\|borde\|ruteo\|plan-borrar\|borrar\|migrar` | `aegis org plan\|apply\|validate\|edge\|routes\|plan-delete\|delete\|migrate` |
| | `aegis-secreto --todos\|--rotar\|--reubicar` | `aegis secret create\|rotate\|move` |
| **operate** | `aegis-chequeo` | `aegis check` |
| | `aegis-sync --fuera-de-linea` | `aegis sync --drifted` |
| | `ai status\|init\|abrir\|cerrar\|max\|demo\|log` | `aegis ai status\|start\|stop\|max\|demo\|logs` |
| **infra** | `aegis-borde` | `aegis edge check` |
| | `aegis-webhook --aplicar` | `aegis webhook check\|apply` |
| | `aegis-registro --revisar\|--rotar` | `aegis registry check\|rotate` |
| | `aegis-rotate.sh` | `aegis rotate` |
| **backup** | `aegis-backup.sh` / `aegis-restore.sh` | `aegis state backup\|restore` |
| | `aegis-respaldo --capturar\|--listar\|--restaurar` | `aegis data backup\|list\|restore` |
| **dev** | `aegis-semilla` | `aegis dev seed` |
| | `aegis-org-prueba`, `aegis-tipos-prueba` | `aegis dev test-org`, `aegis dev test-types` |

### Dos colisiones que el renombrado destapó

**`backup` chocaba consigo mismo.** `aegis-backup.sh` guarda los tres estados
que solo viven en la VM; `aegis-respaldo` guarda los datos de los inquilinos.
En español la colisión no se veía porque una decía "backup" y la otra
"respaldo"; en inglés los dos son *backup*. De ahí `state` y `data`.

**`ai init` chocaba con `aegis init`.** Uno enciende la GPU por N horas, el otro
instala la plataforma entera. Como subcomandos del mismo binario eso es una
trampa esperando a alguien cansado. De ahí `ai start`.

### Lo que NO entra en la CLI del operador

`aegis-semilla` y las dos pruebas de aceptación son herramientas de **quien
mantiene aegis**, no de quien lo opera. Van bajo `aegis dev ...` o directamente
fuera del despachador. kubectl no distribuye su suite de tests.

---

## 5 · Reglas de diseño que vienen del registro

Estas no son preferencias: son los siete casos de Enfermedad E convertidos en
condiciones que el código nuevo debe cumplir.

1. **Ningún invocador sin guarda.** Todo lugar que ejecuta otro comando
   verifica primero que exista, o trata el 127 explícitamente. La rama
   "no evaluable" no puede compartir código con "no existe".
2. **Ningún estado comunicado por prosa.** Un comando que necesita saber qué
   hizo otro lo lee de un rc o de una línea máquina-legible estable
   (`STATE=created`), **jamás grepeando un mensaje traducible**. Hoy
   `aegis-app:713` grepea `"webhook creado"` y ese acople es la única bomba
   que se activa al tocar la capa de mensajes.
3. **Ninguna ausencia se interpreta como caso legítimo sin distinguirla de un
   error.** Si el check 4 no encuentra el generador, tiene que preguntarse si
   hay contratos: sin contratos es normal, con contratos es un fallo.
4. **`return 0` jamás significa "no pude hacerlo".** `aegis-rotate.sh:757`
   devuelve éxito cuando falta el sincronizador.
5. **Un mensaje de fallo no atribuye una causa que no verificó.**
   `aegis-rotate.sh:243/641` manda a escribir un verificador que ya existe.
6. **Todo centinela parseado y el texto que lo produce viven en el mismo
   archivo**, o hay un check que exige que coincidan.
7. **Todo comando declarado existe, es ejecutable y se anuncia.** El diente de
   la sección 2.

---

## 6 · Deuda heredada que el árbol nuevo no debe heredar

Del registro, sección H — cosas que **ya están rotas hoy**:

- `aegis-rotate.sh` se anuncia como `aegis-rotar`, un nombre que no existe.
- Los `.tf` citan `aegis-rotate --verificar`, sin el `.sh`.
- `docs/protocols/organization.md` documenta `aegis org rotar <org> <secreto>`,
  un subcomando fantasma.
- **35 archivos generados llevan `aegis org` (la forma despachador, que todavía
  no existe) y `bin/aegis-org` en el mismo banner**, más un tercer formato de
  banner conviviendo. El generador debe emitir **una** convención para que la
  re-derivación normalice los 38 de una pasada.
- Las dos pruebas de aceptación son huérfanas: nadie las corre, `verify-static`
  no las invoca, no hay CI.

---

## 7 · Abierto

- **¿El vocabulario del contrato pasa a inglés?** Decidido que no por ahora
  (`organizacion:`, `usa:`, `cuota:` se quedan). Si alguna vez sí, es una
  migración versionada con `aegis org migrate` y `version: 2`, nunca un
  buscar-y-reemplazar: renombra objetos vivos de Kubernetes.
- **¿`aegis dev` entra al despachador o queda afuera?**
- **¿`initiatedBy.username: "aegis-sync"`** se renombra? Queda grabado en el
  historial de operaciones de ArgoCD; es un dato, no un comando.

---

## 8 · El primer arranque: el perfil local y el dominio después

**Decidido el 2026-08-22.** Aegis instala **sin dominio**. El wizard pregunta
«¿tenés un dominio en Cloudflare?» y bifurca; el que no tiene, tiene plataforma
igual. Es el test del amigo tomado en serio: el amigo casi nunca tiene dominio.

### No es un modo: es otro valor

`ROOT_DOMAIN` ya es una variable en todo el árbol — derivaciones, rutas,
contratos y sondas no saben qué valor lleva. El perfil local pone
`127-0-0-1.sslip.io` (o `<ip-lan-con-guiones>.sslip.io` para entrar desde el
teléfono) y el 90% del sistema ni se entera. sslip.io es un DNS público cuya
respuesta viene escrita en la pregunta: `blog.127-0-0-1.sslip.io → 127.0.0.1`.
Sin cuenta, sin registro, sin nada que expire — el nombre ES la dirección.

Las diferencias reales son CUATRO, y solo cuatro:

| pieza | con dominio | local |
|---|---|---|
| fase 25 (túnel + DNS + Access) | corre | se salta |
| certificados | Let's Encrypt | CA interna (ya existe: el registry vive de ella) |
| CI push→build | webhook de GitHub | sondeo periódico del multibranch (una línea en la derivación de jobs — hoy los jobs derivados NO llevan trigger periódico y dependen 100% del webhook) |
| sondas de sitio | camino completo por Cloudflare | contra traefik directo, DICIENDO que miden menos |

Por qué CA interna y no Let's Encrypt: LE limita emisión POR DOMINIO
REGISTRADO; con sslip.io el límite se comparte con todos sus usuarios del
mundo. No es una opción declinada — no existe.

### El protocolo de adopción de dominio (`aegis domain set`)

Agregar el dominio después NO es reinstalar, porque todo lo que lleva el
dominio adentro o se DERIVA (aegis-org), o se RENDERIZA (fase 10), o está en
los CONTRATOS. El protocolo: (1) zona en Cloudflare + tokens; (2) ROOT_DOMAIN
nuevo + `dominio:` en los contratos; (3) re-render + re-derivación (mecanismos
existentes); (4) fases 25 y 60, idempotentes; (5) issuer swap CA→ACME.

La ÚNICA pieza nueva es el comando que orquesta y verifica esos pasos:
`aegis domain set <dominio>`. Vale más allá del perfil local — también es el
camino de MIGRAR de dominio, que hoy no existe.

### Arrugas registradas (para no redescubrirlas)

- **La IP viaja en el nombre**: DHCP cambia la IP → cambian los nombres LAN.
  Default `127-0-0-1` (nunca cambia); la forma LAN es opt-in.
- **sslip.io es un tercero**: su DNS caído = nombres locales sin resolver con
  todo lo tuyo vivo. Salida de emergencia: `/etc/hosts` derivado (patrón que el
  init ya usa para el registry).
- **La CA en el navegador**: curl y containerd la toman del trust del sistema;
  Firefox/Chrome usan store propio. Un paso guiado del wizard, o aviso claro.
- **ntfy desde el teléfono**: exige la forma LAN + la CA instalada en el
  teléfono (o http plano en LAN). Resolver en implementación, no improvisar.
