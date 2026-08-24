# Protocolo: organizaciones y servicios

Estado: **contrato v1**. Este documento define la superficie que un
operador —humano o agente— toca para crear organizaciones y servicios en
aegis. Está escrito para no volver a tocarse: lo que cambia con el tiempo
son los PLANES y la TABLA DE RUTEO, no este contrato.

Audiencia: el operador de una instancia de aegis. No hace falta ser el
autor de aegis para leerlo. Si sos un agente, la sección
[§10](#10-si-sos-un-agente) te dice exactamente qué ejecutar y qué nunca
inventar.

---

## 0. Por qué existe

Hoy crear una organización son seis archivos YAML escritos a mano, dos
ceremonias de secretos y una cantidad de pasos que solo viven en la
cabeza de quien ya lo hizo. Eso funciona una vez. No funciona para un
producto donde el autor es un cliente más.

El problema no es la cantidad de YAML: es que **no hay un lugar donde
esté escrito qué es una organización**. Cada una salió parecida a la
anterior por imitación, y las diferencias entre ellas no son decisiones
—son accidentes de cuándo se creó cada una.

Este protocolo mueve eso a un contrato de un archivo y un generador que
lo materializa.

---

## 1. El modelo, en cuatro frases

Una **organización** es un proyecto: `veterinaria`, `pasteleria`,
`portafolio`. Vive en un namespace propio, tiene su cuota, su aislamiento
de red y su frontera de seguridad.

Un **servicio** es una pieza desplegable dentro de una organización: un
front, una API, una base, un worker. Una organización tiene varios.

Los **servicios de plataforma** son compartidos por todas las
organizaciones: el almacenamiento S3 (Garage), el sustrato de AI, el
registry, el CI. Nadie los instala por organización; se les pide acceso.

El **contrato** es un archivo YAML por organización. Es lo único que se
escribe a mano.

```
orgs/veterinaria.yaml     ← contrato (a mano)
        │
        │  aegis org apply
        ▼
k8s/organizations/org-veterinaria/…   ← generado
k8s/argocd-apps/tenants.yaml          ← generado (entrada)
        │
        │  git commit + push
        ▼
    ArgoCD despliega
```

---

## 2. La inversión que hace que esto dure

**El contrato expresa INTENCIÓN. La plataforma impone GARANTÍAS.**

Un contrato no puede pedir menos seguridad de la que la plataforma exige
hoy, ni quedar exento de la que exija mañana. Cuando el piso sube, sube
para todas las organizaciones a la vez, sin editar ni un contrato.

Concretamente, esto NO es configurable desde un contrato y nunca lo será:

| Garantía | Dónde se impone |
|---|---|
| Solo imágenes firmadas por esta plataforma | Kyverno `require-aegis-signature`, alcance por etiqueta de namespace |
| La organización no puede crear recursos cluster-scoped | AppProject `aegis-tenant-<org>` con `clusterResourceWhitelist: []` |
| Todo tráfico denegado salvo lo concedido | NetworkPolicy `default-deny` en cada namespace |
| Todo container declara `limits` | ResourceQuota del namespace |
| Los secretos viajan cifrados en git | SOPS + age, KSOPS al desplegar |

Un contrato pide *acceso al bucket* o *dos tareas de AI*. No pide
"desactivar la verificación de firma". Esa opción no existe en el
esquema, que es la única forma de que no exista nunca.

**Corolario para las generaciones.** Una organización creada bajo
contrato v1 sigue funcionando cuando la plataforma llegue a v3, porque
lo que envejece es el RENDER (que el generador mantiene por versión) y
no las garantías (que se aplican a todas por igual). Ver
[§8](#8-versiones-y-migración).

---

## 3. El contrato

Un archivo por organización en `orgs/<nombre>.yaml` del repo de
plataforma.

```yaml
# orgs/veterinaria.yaml
version: 1                      # OBLIGATORIO. Ver §8.
organizacion: veterinaria       # [a-z][a-z0-9-]{2,30}. Namespace = org-<nombre>.
dominio: veterinaria.__ROOT_DOMAIN__

# Cuota: un PLAN CON NOMBRE, nunca números sueltos.
# Los números viven en platform/plans.yaml y se pueden reajustar para
# todas las organizaciones a la vez. Si acá hubiera `cpu: 4`, treinta
# archivos habría que editar el día que cambie el hardware.
cuota: pequena                  # pequena | mediana | grande

almacenamiento:
  bucket: true                  # bucket propio en el Garage compartido

ai:
  plan: basico                  # basico | estandar | intensivo
  tareas:
    # La organización nombra una CAPACIDAD, jamás un modelo ni un
    # proveedor. Ver §5.
    - {nombre: chat.recepcion, capacidad: chat.rapido, prompt: recepcion.txt}
    - {nombre: npc.mascota,    capacidad: chat.rapido, prompt: mascota.txt}

servicios:
  - nombre: front
    tipo: estatico              # nginx sirviendo un build
    repo: github.com/ORG/veterinaria-front
    publico: /                  # ruta bajo `dominio`
    # SIN `usa`: un front estático no tiene dónde guardar una
    # credencial. Lo que necesite AI o bucket va detrás del `http`.
  - nombre: api
    tipo: http
    repo: github.com/ORG/veterinaria-api
    puerto: 8080
    publico: /api
    usa: [bucket, ai, postgres] # concesiones de red explícitas
  - nombre: db
    tipo: postgres              # lo provee la plataforma: sin repo
  - nombre: recordatorios
    tipo: worker                # no escucha: procesa
    repo: github.com/ORG/veterinaria-cron
    usa: [postgres]
```

### Qué significa cada `tipo`

Un tipo que no restringe nada no es un tipo, es una etiqueta. Cada uno
acota qué campos tienen sentido, y el generador **rechaza** lo que no:

| tipo | quién lo trae | `puerto` | `publico` | `usa` |
|---|---|---|---|---|
| `estatico` | repo del tenant | ✗ (la plataforma sirve en 8080) | **obligatorio** | ✗ **prohibido** |
| `http` | repo del tenant | **obligatorio** | opcional | opcional |
| `worker` | repo del tenant | ✗ | ✗ | opcional |
| `postgres` | **la plataforma** | ✗ (5432) | ✗ nunca | ✗ |

De todas, la única que es de **seguridad** y no de coherencia es
`estatico` sin `usa:`. Un front estático no tiene lado servidor: cada
byte que se le entrega viaja al navegador, así que una credencial ahí
está publicada. Lo que necesite hablar con la AI o con el bucket va
detrás de un `http` — que es exactamente el rol del BFF, y lo que ya
dicen los contratos del portafolio y el blog en un comentario. Ahora lo
dice el generador.

`postgres` es el primer tipo **provisto por la plataforma**: no lleva
repo, y su imagen (firmada, por digest), su disco y su credencial salen
de `services.yaml`. Una base por organización, nunca compartida — un
`DROP` de una no puede tocar a la vecina.

`aegis dev test-types` recorre cada regla con su contraejemplo y exige
que el generador la rechace **nombrando la razón correcta**: un rechazo
por el motivo equivocado saldría verde igual, y ese es un error que ya
se cometió cuatro veces esta semana.

### Reglas del esquema

1. **Campos desconocidos = error.** No se ignoran en silencio. Un typo en
   `almacenamineto:` tiene que fallar ruidoso, no desactivar el bucket sin
   avisar.
2. **Sin números de infraestructura.** Ni CPU, ni memoria, ni tokens por
   minuto, ni réplicas. Todo eso es un plan con nombre.
3. **Sin nombres de modelos ni proveedores.** Ver §5.
4. **`usa:` es una lista blanca.** Un servicio que no declara `bucket` no
   puede llegar al Garage — no por convención, sino porque la
   NetworkPolicy generada no lo permite.
5. **El nombre es inmutable.** Cambiarlo no renombra: crea otra
   organización. El generador lo detecta y lo dice.

---

## 4. El generador

```
aegis org apply orgs/veterinaria.yaml      # renderiza a git
aegis org apply orgs/*.yaml                # todas
aegis org plan    orgs/veterinaria.yaml      # muestra el diff, no escribe
aegis org delete  veterinaria                # ver §7
```

**El generador NO habla con el cluster.** No tiene `kubectl` en su
camino. Escribe archivos en el repo y termina. Quien despliega es ArgoCD,
después de que vos revises el diff y commitees. Esto no es purismo: es lo
que hace que un `aegis org apply` sea seguro de correr en cualquier
momento, incluso mal, porque lo peor que puede pasar es un diff feo que
no commiteás.

### Lo que se DERIVA de todos los contratos

Además del directorio de cada organización, el generador rederiva ocho
archivos que dependen del conjunto — no del contrato que acabás de
tocar:

| Archivo | Qué sale de ahí |
|---|---|
| `tofu/envs/cloudflare-tunnel/main.tf` | los `public_hostnames` del borde |
| `k8s/base/ai-system/routes.yaml` | el mapa organización → plan de AI |
| `k8s/bootstrap/appprojects-tenants.yaml` | el AppProject de cada organización con repo |
| `k8s/base/platform/argocd-secrets/secret-generator.yaml` | la deploy key con la que ArgoCD lee cada repo |
| `k8s/argocd-apps/tenants.yaml` | la Application que despliega cada organización |
| `k8s/base/garage-system/aprovisionar.yaml` | un Job por organización que pidió bucket |
| `k8s/base/garage-system/kustomization.yaml` | si `aprovisionar.yaml` se incorpora o no |
| `k8s/base/garage-system/secret-generator.yaml` | los espejos de credencial S3 que KSOPS descifra |

#### Los AppProjects (2026-08-05, #19)

El AppProject **es** la frontera de permisos de una organización: de qué
repo puede leer, en qué namespace puede escribir, y que no puede tocar
nada cluster-scoped. Se deriva **solo para los contratos que declaran
repo**: una organización de pura infraestructura no tiene ninguna
Application externa, y un proyecto sin `sourceRepos` no acota nada.

Se derivó por dos cosas que se midieron, no por prolijidad:

1. **Faltaba uno.** `org-ejemplo` tenía contrato y no tenía proyecto. En
   cuanto declarara `repo:`, su Application quedaría en *project not
   found* — un error que llega tarde, después del repo, el pipeline y el
   push.
2. **Los repetidos derivan.** `aegis-tenant-canary` era el único de los
   cuatro proyectos de tenant sin `orphanedResources`: quedó afuera
   cuando #31 lo agregó a los otros tres. Consecuencia real: la app del
   canary no se evaluaba nunca y `aegis check` la contaba dentro
   de *"nada huérfano"*. **Un bloque copiado tres veces se actualiza
   dos.** Derivado, los bloques son idénticos por construcción y no por
   disciplina.

Lo que **no** se deriva y sigue a mano en `k8s/bootstrap/appprojects.yaml`:
`aegis-bootstrap` y `aegis-platform` (son del sustrato, no de ninguna
organización), `aegis-tenant-canary` (el canary es de la plataforma:
prueba que el camino del tenant funciona, así que no puede depender de
ese camino) y `aegis-tenant-ecommerce` (heredado, mismo criterio que
`tenants-heredados.yaml`).

**Estos NO los aplica ArgoCD**, a propósito (W-06 / R1-B): los aplica
`kubectl` en la fase 35, antes de root. Eso evita la carrera
AppProject-vs-Application dentro de un mismo sync y cierra el vector de
escalar privilegios por una App que edite proyectos. Como consecuencia,
al dar de alta una organización hay un paso más:

```
kubectl apply -f k8s/bootstrap/appprojects-tenants.yaml   # ANTES
bin/aegis-sync root                                       # DESPUÉS
```

El generador lo imprime cada vez que reescribe el archivo. Y el
invariante «toda Application referencia un AppProject definido» lo
comprueba `init/verify-static.sh` (check 76) contra el repo, sin
cluster: se verifica que referencias ⊆ definiciones, no una lista de
nombres — una lista sería un quinto lugar donde acordarse.

#### La deploy key de repositorio (2026-08-05, #48)

ArgoCD necesita una credencial para leer un repo privado, y esa
credencial es de la organización aunque el Secret viva en el namespace
de ArgoCD: sale de su `repo:` y desaparece con ella.

Estaba en el peor de los estados posibles. Las dos que existían —blog y
portafolio— se habían escrito a mano con `sops`, **nadie las producía**,
ningún protocolo las documentaba y la checklist de rotación no las
nombraba. El síntoma llega en una instancia nueva: ahí la age key es
otra, el init recifra todo lo que sí produce, y estas dos quedan
cifradas con una llave que ya no existe. KSOPS no las descifra y la App
`argocd-secrets` no sincroniza nunca.

Ahora `aegis secret create <contrato>` las crea en la misma pasada
que el resto de los secretos de la organización, y el generador las
lista solo. El material se genera con `ssh-keygen` en tmpfs y se borra
con `shred` — el mismo mecanismo que el init usa para la propia age key.

**Queda un paso a mano, y es irreducible:** la mitad PÚBLICA hay que
registrarla en GitHub. El comando la imprime y dice qué hacer:

```
<repo> → Settings → Deploy keys → Add deploy key
título: aegis-argocd-ro      SIN "Allow write access"
```

Sin escritura, y eso importa: ArgoCD solo LEE. Una deploy key con
escritura deja que quien tenga el cluster escriba en el repo de la app,
que es la dirección equivocada.

Dos de los ocho son **el cableado** de garage, y están derivados por lo que pasó
el 2026-08-04: estaban escritos a mano, y el generador escribía dentro
de `garage-system/` dos archivos que ninguno de los dos listaba —
`aprovisionar.yaml` y `secret-garage-<org>.enc.yaml`. El síntoma era el
peor posible: `aplicar` decía que todo salió bien, los archivos quedaban
en git, y en el cluster no pasaba nada. Sin error, en ningún lado.

**Un archivo generado que nadie lista es un archivo que no existe.** Si
el generador escribe en un directorio, tiene que derivar también el
cableado de ese directorio — o el cableado tiene que ser un glob, y los
globs están prohibidos por A7 para los secretos.

La misma corrida barre los espejos que sobran: si una organización se
borra, o le sacás el bucket del contrato, su `secret-garage-<org>.enc.yaml`
desaparece de `garage-system/`. Ojo con qué significa eso — borrarlo del
repo **no revoca la clave** en Garage; eso es `garage key delete` contra
el almacén.

Los ocho corren **siempre**, al final de `plan`, `aplicar` y `borrar`.
No son subcomandos que haya que acordarse de correr: acordarse es lo que
ya falló dos veces con el borde. Y corren sobre TODOS los contratos
porque dar de alta una organización cambia el conjunto entero — su
hostname, su plan y su Application aparecen o desaparecen solos.

El caso que esto cierra es el peor de todos: antes, `tenants.yaml` se
editaba a mano. Olvidarse daba **todo generado, todo commiteado y nada
desplegado**, sin un solo error a la vista.

Las organizaciones anteriores al generador viven en
`tenants-heredados.yaml`, a mano y a propósito: mezclarlas en el archivo
generado haría que la próxima corrida las borrara en silencio.

### Las reglas de idempotencia

Son el corazón del protocolo. Sin ellas "idempotente" es una palabra.

**I1 — Mismo contrato, salida byte a byte idéntica.** Sin marcas de
tiempo, sin UUIDs, sin orden de mapa dependiente del intérprete. Correr
dos veces seguidas deja el árbol de git limpio la segunda vez. Es
verificable y el CI lo verifica.

**I2 — Los secretos se crean si faltan y NUNCA se regeneran.** Un
`aegis org apply` sobre una organización viva no rota ninguna
credencial. Rotar es un acto deliberado y tiene su propio comando:
`aegis secret rotate <archivo.enc.yaml>`.

(Hasta el 2026-08-23 este renglón decía «aegis org rotar» (sin comillas
invertidas acá a propósito: en este documento las comillas invertidas
son invocaciones, y el check 106 las verifica una por una), un comando
que NUNCA EXISTIÓ. Quien lo tecleaba no recibía un error útil sino un
«subcomando inválido», y la conclusión natural es «me equivoqué yo», no
«el documento está viejo». Lo encontró el check 106, que extrae de los
documentos toda invocación citada y exige que exista: los documentos
que el operador ejecuta son código con otra sintaxis, y envejecen
igual.) Sin esta regla nadie se anima a
correr el generador dos veces, y un generador que da miedo no es
idempotente aunque lo sea.

**I3 — Los archivos generados llevan cabecera y hash.**

```yaml
# GENERADO POR aegis org — DO NOT EDIT BY HAND.
# contrato: orgs/veterinaria.yaml
# hash: sha256:3f9a…   (del contrato que lo produjo)
```

Si el archivo cambió a mano, el hash no coincide y el generador **se
niega y muestra la diferencia**, en vez de pisarla. La salida es el
contrato, no el archivo.

**I4 — Convergencia, no acumulación.** Sacar `bucket: true` del contrato
y reaplicar QUITA la NetworkPolicy del bucket. El generador es dueño del
directorio de la organización entero.
Advertencia heredada: **quitar un recurso de git no lo quita del
cluster** (`prune` omitido, A19). Por eso `aegis org apply` avisa
explícitamente qué archivos borró y qué hay que hacer con ellos. Ver §7.

**I5 — El contrato inválido no produce nada.** Se valida entero antes de
escribir el primer archivo. Nunca un árbol a medio generar.

### Qué emite

```
k8s/organizations/org-veterinaria/
  bundle.yaml            Namespace (con la etiqueta de enforce), ResourceQuota,
                         LimitRange, ServiceAccount default con regcred
  appproject.yaml        AppProject aegis-tenant-veterinaria, cluster-scoped []
  netpol.yaml            default-deny + las concesiones que pidió el contrato
  apps.yaml              una Application de ArgoCD por servicio
  secret-*.enc.yaml      SOLO si faltan (I2)
  kustomization.yaml
k8s/argocd-apps/tenants.yaml    entrada de la organización
```

Y, si el contrato lo pide, dos registros en plataforma:

- las tareas de AI en el registro del gateway,
- el bucket y su credencial en el Garage.

---

## 5. AI: capacidades, planes y proveedores

Este es el pedazo diseñado para que agregar Vertex, Bedrock o créditos de
un tercero **no toque ninguna organización**.

### La organización pide una CAPACIDAD

```yaml
ai:
  plan: basico
  tareas:
    - {nombre: chat.recepcion, capacidad: chat.rapido, prompt: recepcion.txt}
```

Una capacidad es una promesa de comportamiento: *chat.rapido* significa
"responde en pocos segundos, contexto corto". No dice con qué. Una
organización que nombrara `qwen3-4b` quedaría casada con una decisión de
infraestructura que no le corresponde, y el día que ese modelo se
reemplace habría que editar todas.

Capacidades del contrato v1:

| Capacidad | Promesa |
|---|---|
| `chat.rapido` | respuesta conversacional, contexto corto, latencia baja |
| `chat.largo` | contexto amplio, latencia mayor tolerada |
| `embeddings` | vectores para búsqueda semántica |
| `transcripcion` | audio a texto |

### La plataforma decide CON QUÉ

`platform/ai/routes.yaml`, plano de plataforma, fuera del alcance de las
organizaciones:

```yaml
capacidades:
  chat.rapido:
    proveedor: local
    modelo: qwen3-4b
    contexto_max: 12288
  chat.largo:
    proveedor: local
    modelo: qwen3-4b
    contexto_max: 12288

# El día que haya créditos de un tercero, esto es TODO el cambio:
#
#   chat.largo:
#     proveedor: vertex
#     modelo: gemini-x
#     credencial: secret-vertex-veterinaria   # o de plataforma
#     contexto_max: 1000000
#
# Cero organizaciones tocadas. Cero contratos migrados.
```

**Regla de proveedores:** un proveedor nuevo se agrega implementando la
interfaz del gateway (generar, con streaming y con corte por
presupuesto). No se agrega metiéndole un `if` al camino de la request.

**Regla de costo:** un proveedor pago tiene presupuesto en la MISMA
moneda que el local — tokens, no requests — para que un cambio de ruteo
no cambie el significado de un plan. Un plan `basico` cuesta lo mismo al
usuario tanto si atrás hay una GPU propia como si hay una factura.

**Solo se declara lo que se sabe servir.** `ai/routes.yaml` no lleva
capacidades "reservadas para más adelante". El gateway rechaza al
ARRANCAR un proveedor que no tenga cliente implementado, y `bin/aegis-org`
saca de este archivo la lista de capacidades que un contrato puede
nombrar. Una capacidad declarada de antemano sería un contrato válido
que revienta recién cuando un visitante lo invoca: el error aparecería
lejos de la causa, que es la forma más cara de equivocarse.

> La versión anterior del generador tenía la lista de capacidades
> escrita a mano e incluía `embeddings` y `transcripcion`, que todavía
> no tienen engine. Un contrato que las pidiera pasaba la validación y
> después impedía que el gateway arrancara.

### Cómo llega al gateway

El gateway no lee ninguno de estos archivos: lee un ConfigMap. Lo
**genera** `bin/aegis-org` combinando tres fuentes, y por eso el mapa
organización→plan no se escribe a mano en ningún lado.

```
ai/routes.yaml   ─┐
platform/plans.yaml ─┼─→  k8s/base/ai-system/routes.yaml  (ConfigMap ai-ruteo)
orgs/*.yaml     ─┘                    ↓  montado en /etc/ai-ruteo
                                  ai-gateway
```

| Fuente | Aporta | Quién la edita |
|---|---|---|
| `ai/routes.yaml` | `capacidades` | plataforma |
| `plans.yaml` | `planes` | plataforma |
| `orgs/*.yaml` (`ai.plan`) | `tenants` | cada organización |

Se regenera **siempre** al final de `aegis-org plan` y `aegis-org
aplicar`, igual que el borde, y por la misma razón: dar de alta una
organización cambia el mapa entero, no solo su fila. Si hubiera que
acordarse de correr un comando aparte, el síntoma sería un gateway que
arranca sin conocer a la organización recién creada — y un tenant
desconocido cae al plan más chico, en silencio.

La clave del mapa es el **namespace** (`org-portafolio`), no el nombre
corto del contrato: es lo que el gateway recibe en la API key.

### Los planes

`platform/plans.yaml`:

```yaml
ai:
  basico:    {tokens_min: 600,   concurrencia: 2, prioridad: 3, reserva: 0.15}
  estandar:  {tokens_min: 4000,  concurrencia: 2, prioridad: 2, reserva: 0.25}
  intensivo: {tokens_min: 12000, concurrencia: 4, prioridad: 1, reserva: 0.35}
```

Cuatro números y cada uno acota algo distinto:

| Campo | Qué acota | Alcance |
|---|---|---|
| `tokens_min` | presupuesto de salida | **organización** |
| `concurrencia` | pedidos suyos en la GPU a la vez | **organización** |
| `prioridad` | a quién se despierta primero (menor = antes) | plan |
| `reserva` | fracción del cupo garantizada | **plan** |

`prioridad` es lo que ordena la cola cuando hay contención: con una sola
GPU detrás, dos organizaciones pidiendo a la vez tienen que resolverse de
alguna manera, y "quien llegó primero" castiga a quien paga más.

`reserva` es el contrapeso, y es lo que impide que eso degenere en
exclusividad: por bajo que sea el plan, esa fracción del cupo le queda
siempre. **Un plan alto compra latencia, no el derecho a dejar a otro sin
turno.**

**La reserva es por PLAN y no por organización.** Si fuera por
organización, diez del plan más chico reservarían su fracción cada una y
el cupo no alcanzaría para ninguna. Por plan, el conjunto de los básicos
comparte su porción — que es lo que la palabra significa. La
`concurrencia` sí es por organización, porque ahí lo que se acota es una
concreta.

Detalle de implementación que conviene conocer: una fracción que
redondea a cero lugares se sube a **uno**. Una reserva declarada que no
reserva nada no es una reserva, y con cupos chicos (4 lugares) cualquier
fracción menor a 0,25 caería ahí. Si la suma pasa el 100%, se escalan
todas proporcionalmente en vez de fallar — un ruteo mal sumado no debe
poder dejar al gateway sin arrancar.

**Los números viven acá y en ningún otro lado.** Reajustarlos es editar
un archivo, no treinta. Las cuotas de CPU/memoria viven en el mismo
archivo bajo `cuota:`, con los mismos escalones con nombre.

---

## 6. Secretos

Cada organización necesita, según lo que pida:

| Secreto | Cuándo | Origen |
|---|---|---|
| `regcred-internal` | siempre | credencial de lectura del registry interno |
| `ai-gateway-key` | si hay `ai:` | clave `aegisk_…` emitida por el gateway |
| `garage-<org>` | si hay `bucket:` | par de claves S3 del bucket propio |

```
aegis secret create orgs/veterinaria.yaml    # crea los que falten
aegis secret --rotar <archivo>                # deliberado, de a uno
```

`bin/aegis-org` **no** crea secretos: escribe manifiestos y no maneja
material criptográfico. Separar las dos cosas es lo que permite correr
el generador sin pensarlo. Cuando falta alguno, lo lista con el comando
exacto para crearlo.

Reglas, todas consecuencia de I2:

1. **Crear si falta, jamás sobreescribir.** Reaplicar no rota. Es un
   mecanismo, no una promesa: `aegis-secret` sobre un archivo que
   existe dice "no se toca" y sale.
2. **El operador no ve el material.** Se genera con `secrets` (no
   `random`, que es un Mersenne Twister predecible), se le pasa a `sops`
   **por stdin** y lo único que toca el disco es el archivo cifrado. No
   pasa por `argv` ni por un temporal legible.
   Cifrar **no necesita la age key privada**, solo el recipient público
   de `.sops.yaml`: crear credenciales nunca obliga a materializar la
   llave que descifra todo.
3. **Nunca en `argv`.** Ni local ni remoto. Por stdin o por archivo con
   permisos 600 (regla A27 del init).
4. **Se verifica por resultado, no por lectura.** El chequeo de que un
   secreto quedó bien es que el pod arranca y autentica, no que alguien
   lo imprimió. Hay un incidente registrado sobre esto:
   `ai-tenant-key.md` §3 documenta un chequeo que respondía "OK" leyendo
   el primer carácter de un mensaje de error.
5. **Rotar es un comando aparte**, deliberado, con su propia bitácora.
   `--rotar` va de a uno y es incompatible con `--todos`: rotar en lote
   es cómo se rota algo que no se quería rotar.

**Lo que rotar NO hace.** Genera la credencial nueva y nada más. La
vieja sigue siendo válida donde la acepten: rotar `ai-gateway-key` no
revoca nada hasta que se quite la entrada de
`secret-ai-keys.enc.yaml` — un archivo compartido entre organizaciones,
que por eso no se edita solo. El comando lo dice al rotar, en rojo.

---

## 7. Borrar una organización

```
bin/aegis-org plan-borrar veterinaria    # muestra todo, no toca nada
bin/aegis-org borrar      veterinaria
```

Hoy esto es el punto más débil del protocolo y conviene decirlo antes que
descubrirlo: **`prune` está omitido en toda la plataforma (A19)**, así que
quitar archivos de git no quita nada del cluster.

Por eso `borrar` hace dos cosas separadas y en este orden:

1. Quita el contrato y los archivos generados. Eso es git y es
   reversible. Las tres derivaciones (borde, ruteo, `tenants.yaml`)
   corren después, así que su hostname, su plan y su Application
   desaparecen **solos** — salen de los contratos, no de listas aparte.
2. **Imprime** los comandos exactos para retirar lo que quedó vivo y no
   los ejecuta.

No los ejecuta porque borrar un namespace se lleva puestos los datos, y
eso no puede pasar por un comando que alguien corrió con un nombre mal
tipeado. El día que #31 se resuelva, el paso 2 puede volverse automático
con confirmación.

Los comandos del paso 2 salen ordenados de menos a más destructivo, y
**las Applications van primero**: mientras vivan, reconcilian y recrean
lo que borres. Sus nombres se derivan del contrato, no se dejan a ojo —
es justo ese paso donde un nombre tipeado a mano borra la organización
de al lado.

Dos avisos que el comando imprime porque son los que se descubren tarde:

- **Borrar un `.enc.yaml` no revoca nada.** La credencial sigue siendo
  válida donde la acepten. Revocar es parte del paso 2, y va antes de
  borrar el archivo si querés poder auditarla después.
- **Los PVC pueden sobrevivir al namespace** según la `reclaimPolicy`.
  Se comprueba después, que es cuando se nota.

Dos cosas quedan a mano a propósito, porque viven en archivos
COMPARTIDOS que el generador no gobierna: las tareas `<org>.*` del
registro de AI, y la entrada de la organización en
`secret-ai-keys.enc.yaml`. Editarlos automáticamente significaría que un
`borrar` mal tipeado toca un archivo de todas las organizaciones.

El **AppProject** era la tercera hasta el 2026-08-05 (#19) y ya no lo
es: `appprojects-tenants.yaml` es un archivo derivado, así que el
documento de la organización desaparece solo en la misma corrida. Lo que
sí queda a cargo del operador es **aplicar** el archivo — ArgoCD no
gestiona los AppProjects a propósito, y borrarlos del repo no los saca
del cluster (misma regla A19 que vale para todo lo demás):

```
kubectl apply -f k8s/bootstrap/appprojects-tenants.yaml
kubectl delete appproject -n argocd aegis-tenant-<org>
```

---

## 8. Versiones y migración

`version:` es obligatorio y el generador **rechaza lo que no conoce**. Un
contrato sin versión no es "v1 por defecto": es un error.

- El generador mantiene un renderizador por versión. Un contrato v1 se
  sigue renderizando igual aunque exista v2.
- Una versión nueva se justifica solo si cambia el CONTRATO. Cambiar los
  números de un plan, agregar una capacidad o cambiar el ruteo **no** son
  versión nueva: por eso están afuera.
- Migrar es explícito: `bin/aegis-org migrar orgs/veterinaria.yaml --a 2`
  reescribe el contrato y muestra el diff. Nunca automático al aplicar.
  **Hoy solo existe v1 y el comando lo dice** en vez de fingir: pedir
  una versión que no existe falla nombrando las que sí. Existe ya, y no
  como un TODO, porque el `--a` obligatorio es lo que impide la
  alternativa mala — que alguien suba `version: 2` a mano y descubra
  tarde que el generador no tenía nada nuevo que hacer con eso.
- Las garantías de §2 se aplican a toda organización sea cual sea su
  versión. Un contrato viejo no es un permiso viejo.

---

## 9. Cómo se prueba que esto no es una fantasía

Un protocolo que nadie ejecutó es un deseo. Las pruebas de aceptación,
en orden de dureza:

1. **Reproducir lo que ya existe.** Escribir el contrato de
   `org-portafolio` —que hoy está a mano y desplegado— y verificar que el
   generador produce lo mismo que está corriendo. Si no lo reproduce, el
   modelo está mal, no la organización.
2. **Idempotencia real.** `aplicar` dos veces seguidas deja el árbol
   limpio la segunda. Lo verifica el CI, no una persona.
3. **Alta de punta a punta.** Un contrato nuevo hasta un `curl` con TLS
   contra el servicio desplegado, sin ningún paso manual fuera del
   commit.
4. **El piso se sostiene.** En la organización nueva, una imagen sin
   firmar es RECHAZADA por admisión, y un pod suyo no alcanza a otra
   organización. Se prueba ejerciendo el invariante, no leyendo el YAML
   —la lección de `aegis check` y de la Enfermedad B.
5. **Borrar y volver a crear** deja el sistema como al principio.

---

## 10. Si sos un agente

Estas reglas existen porque un agente con un `kubectl` a mano tiende a
arreglar el síntoma.

**Hacé:**
- Leé el contrato antes de tocar nada. La verdad está en `orgs/*.yaml`,
  no en el cluster.
- Para cualquier cambio de una organización: **editá el contrato y
  reaplicá.** Siempre.
- Mostrá el diff antes de commitear.
- Si el generador se niega por hash (I3), mostrá la diferencia y
  preguntá. No la pises.

**No hagas:**
- No edites archivos con la cabecera `GENERADO POR aegis org`. Lo que
  hay que cambiar es el contrato.
- No apliques manifiestos de una organización con `kubectl apply`. El
  camino es git → ArgoCD. Un apply directo queda pisado en el próximo
  sync y mientras tanto miente sobre el estado real.
- No inventes valores de plan ni de cuota. Si el que hace falta no
  existe, el cambio es agregar un plan en `platform/plans.yaml` y
  decirlo.
- No rotes secretos "por las dudas". Rotar es deliberado (§6.5).
- No pongas nombres de modelo ni de proveedor en un contrato (§5).

**Verificá por resultado, no por lectura.** "El YAML dice que la firma se
exige" no es una verificación. Meter una imagen sin firmar y ver que
rebote, sí.

---

## Estado de implementación

Este documento define el contrato. Lo que falta construir está en las
tareas #39–#43. El contrato se considera cerrado; lo que se ajusta con la
implementación son los planes, el ruteo y los tipos de servicio — todo
afuera de este archivo a propósito.
