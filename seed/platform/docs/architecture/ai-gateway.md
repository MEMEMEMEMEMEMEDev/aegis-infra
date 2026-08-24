# ai-gateway — diseño

LA fuente canónica del sustrato de AI multiproyecto. Si este
documento y el código divergen, ES UN BUG: se corrigen juntos.

Estado: diseño cerrado 2026-08-02. Implementación en curso (#23).
Precede a #24 (portafolio consume), #25 (Cloudflare), #26 (carril CPU).

---

## 1. Qué es, y sobre todo qué NO es

El gateway es **la única puerta** entre cualquier cliente y la única
GPU del cluster. Los proyectos no corren AI en sus namespaces: le
hablan al gateway por HTTP.

Lo que NO es, y no va a ser:

- **No es un proxy de LLM.** No existe, ni va a existir, un endpoint
  que acepte un prompt libre. El cliente elige una **tarea del
  registro** y llena huecos. El día que exista `/chat` con prompt
  arbitrario, dejaste de tener un servicio de AI y tenés un proxy
  gratis de OpenAI con tu nombre en el DNS.
- **No es de alta disponibilidad.** Una GPU = una réplica. Dos
  réplicas no dan disponibilidad, dan dos contadores de cuota que no
  se hablan.
- **No arranca solo.** Nada enciende la GPU salvo el operador. La
  automatización solo APAGA (§5).

---

## 2. La asimetría que gobierna todo

Un `POST` le cuesta al atacante ~0 y cuesta **entre 2 y 7 segundos de
GPU**. No es una API donde el techo es CPU y el abuso se paga en la
factura: acá el techo es físico, hay uno solo, y es la misma placa con
la que el operador trabaja.

Corolarios que se aplican en todo el diseño:

1. **Rechazar tiene que ser barato.** Si validar cuesta lo mismo que
   servir, el guard ES el DoS. De ahí el orden de los filtros: lo que
   descarta más por menos, primero (tamaño de body antes de leerlo
   entero; caracteres antes que tokens; tarea inexistente antes que
   presupuesto).
2. **La moneda es el token, no la request.** 10 requests de 20 tokens
   y 10 de 2000 no son el mismo consumo. Los presupuestos se llevan en
   tokens de salida.
3. **El activo a proteger es la máquina del operador**, no una
   factura. Un abuso exitoso no cuesta dinero: cuesta poder usar la
   computadora.

---

## 3. Los números que dimensionan los guards

Medidos en metal (`aegis-exploration/mediciones`, 2026-07-25) y
confirmados en el cluster (2026-07-30). No son estimaciones.

| Magnitud | Valor |
|---|---|
| Throughput agregado, concurrencia 4 | **107 tok/s** = 6.420 tok/min |
| TTFT en frío / con prefijo cacheado | <1 s / **25 ms** |
| Arranque del engine (caché caliente) | **62 s** |
| Respuesta de 40 tokens, caliente | 565–584 ms |
| VRAM con el modelo cargado | 10,7 / 12,2 GB |
| KV cache real en el cluster | **27.840 tokens** |
| KV cache con VRAM limpia | 35.616 tokens |

### 3.1 El techo de concurrencia no es `max_num_seqs`

`max_model_len` es 12.288 y el KV cache medido fue 27.840 tokens:

```
27.840 / 12.288 = 2,26 conversaciones simultáneas
```

Con contexto lleno **no entran 8 secuencias, entran 2**. El
`max_num_seqs: 8` del perfil es una aspiración que solo se cumple si
cada conversación es corta:

| Contexto por conversación | Secuencias que caben |
|---|---|
| 12.288 (máximo) | 2 |
| 4.000 | 6 |
| 2.000 | 8 (topa en max_num_seqs) |

**Consecuencia de diseño:** el cap de contexto por tarea no es
tacañería, es **lo que compra la concurrencia**. Un NPC con 1.500
tokens de contexto permite 8 visitantes simultáneos; el mismo NPC con
historial sin límite permite 2. Por eso el historial es del gateway y
no del cliente (§7.3).

### 3.2 El streaming es obligatorio, no un lujo

107 tok/s repartidos en 4 streams = ~27 tok/s por stream. Una
respuesta de 200 tokens tarda ~7,5 s en completarse. Sin streaming eso
es un spinner de 7 segundos y parece roto. Con streaming, primer token
en <1 s y 27 tok/s corre más rápido de lo que se lee (~7 tok/s).

### 3.3 El prefix cache manda sobre el ORDEN del prompt

TTFT cae a 25 ms con prefijo cacheado: 40x. Eso impone una regla dura:

> El system prompt de cada tarea es **idéntico byte a byte** en cada
> request y va **primero**. Los datos variables (nombre del visitante,
> hora, historial) van SIEMPRE al final.

Meter algo variable arriba del prompt invalida el prefijo y multiplica
el TTFT por 40. Es el error más fácil de cometer y el más difícil de
notar: no falla nada, solo se pone lento.

---

## 4. Topología

```
                    ┌──────────────────── ai-system ────────────────────┐
                    │                                                   │
navegador           │   ai-gateway                        engine-llm    │
   │                │   ┌──────────────┐                 ┌───────────┐  │
   ├─▶ portafolio.  │   │              │                 │  vLLM     │  │
   │   __ROOT_DOMAIN__ │   │  :8081  ─────┼────────────────▶│  :8000    │  │
   │      │         │   │  interna     │                 │  0 ↔ 1    │  │
   │      ▼         │   │              │                 └───────────┘  │
   │   BFF (Express)├──▶│              │                       ▲        │
   │   org-portaf.  │   │  :8080       │                       │        │
   │   [API key]    │   │  pública     │                 ai-modo-       │
   │                │   │  v1: /status │                 controller     │
   └─▶ ai.example. ├──▶│  solamente   │                 [RBAC mínimo]  │
       com          │   └──────┬───────┘                       ▲        │
                    │          │ lee (volumen montado)         │ observa│
                    │          └────────  ConfigMap ai-modo ───┘        │
                    └───────────────────────────────────────────────────┘
                                          ▲
                                          │ escribe
                                     CLI `ai`  (en la máquina del operador)
```

### 4.1 Dos puertas físicamente distintas

| | :8080 pública | :8081 interna |
|---|---|---|
| Quién llega | traefik ← túnel ← Cloudflare | namespaces de tenant nombrados |
| Credencial | ticket con presupuesto (#25) | API key del proyecto |
| Headers CF | se confían | se **ignoran** |
| v1 sirve | solo `GET /status` | todo |

Dos **puertos** y no dos rutas porque así **la NetworkPolicy puede
obligar a cada origen a usar la suya**. Sin eso, un pod comprometido de
un tenant puede mandar `CF-Connecting-IP` falso y hacerse pasar por
tráfico público; o un visitante intentar la ruta interna. Con dos
puertos, la separación la impone el kernel y no un `if` en el código.

### 4.2 Por qué la puerta pública nace casi vacía

En v1 la inferencia **no es alcanzable desde internet**. El navegador
pasa por el BFF, que tiene la key del lado servidor. `ai.__ROOT_DOMAIN__`
existe igual porque:

- da kill switch y reglas de WAF **independientes del portafolio** —
  se apaga la AI y el sitio queda intacto;
- le da a #25 un blanco al que atarse;
- prueba el camino completo del borde antes de poner algo caro detrás;
- es un chequeo de salud desde afuera del cluster.

Lo único que sirve es un JSON de ~80 bytes, cacheable 10 s. Todo lo
demás responde 404. El endpoint de tickets está **escrito y apagado**
por bandera; #25 lo enciende sin tocar código.

### 4.3 Una imagen, dos binarios, dos ServiceAccounts

`cmd/gateway` y `cmd/controller` salen del mismo repo y de la MISMA
imagen firmada. Son dos Deployments con `command` distinto y cuentas
distintas: **el RBAC vive en la ServiceAccount, no en el binario**.
Ahorra un pipeline entero sin debilitar la separación de §11.

---

## 5. El modo: la fuente única de verdad

Un ConfigMap, `ai-modo`, en `ai-system`. Lo escribe el CLI `ai`, lo
observa el controlador, lo lee el gateway por volumen montado.

```yaml
modo: cerrado          # cerrado | abierto | demo | max
vence: ""              # RFC3339, solo en demo
motivo: "jugando"      # texto libre, para el operador
actualizado: "2026-08-02T14:03:11Z"
```

| Modo | engine | Presupuestos | Vencimiento |
|---|---|---|---|
| `cerrado` | 0 | — (503 dormido) | — |
| `abierto` | 1 | normales | ninguno |
| `demo` | 1 | amplios | **60 min, auto-cierra** |
| `max` | 1 | amplios | ninguno (requiere #25) |

### 5.1 La automatización solo APAGA

Regla dura, sin excepciones: **nada enciende la GPU salvo el
operador**. Lo automático que existe:

- vencimiento del `demo` → `cerrado`;
- horario de cierre opcional → `cerrado`;
- (futuro) tasa de error sostenida → `cerrado`.

No hay auto-abrir, no hay "encender bajo demanda", no hay
scale-from-zero por request. Si alguien entra al portafolio a las 4 AM
ve el mundo dormido, y eso es correcto.

### 5.2 El preflight de VRAM sucia lo hace el CLI

Arrancar el engine con el escritorio ocupando VRAM **recorta el KV
cache de forma permanente** hasta que se reinicie (35.616 → 27.840
tokens medidos, −22%), y con eso la concurrencia real a la mitad.

El chequeo NO va en el cluster: va en el CLI, que corre en la máquina
del operador, donde `nvidia-smi` existe de verdad. `ai abrir` mira la
VRAM libre, y si está sucia **se niega** y dice qué proceso la tiene.
`--force` existe para el que sabe lo que hace.

Cero complejidad dentro del cluster para un problema que vive afuera.

### 5.2.1 El CLI

Vive en `platform/bin/ai` y es lo ÚNICO que enciende. Escribe el
ConfigMap y nada más: no escala, no toca pods, no le habla al gateway.

```
ai status                  qué está pasando ahora
ai abrir [--hasta HH:MM]   enciende (chequea la VRAM antes)
ai demo [minutos]          amplio + TTL, default 60 min, se cierra solo
ai max [--hasta HH:MM]     amplio sin TTL
ai cerrar [motivo]         apaga
ai log [-f] / ai engine-log
```

`--hasta` y el TTL de `demo` escriben el MISMO campo `vence`: un solo
mecanismo para el vencimiento de una demo y para el cierre programado.
Evita depender de tzdata, que una imagen `FROM scratch` no tiene.

### 5.3 El kill switch funciona con el gateway muerto

El CLI escribe el ConfigMap; el controlador escala. El gateway no
participa. Si el gateway está colgado, `ai cerrar` igual apaga la GPU.
Y si el controlador también está caído, queda `kubectl scale` — que
ArgoCD no revierte porque `spec.replicas` está en `ignoreDifferences`.

---

## 6. El registro de tareas

Un ConfigMap. Agregar un NPC es **un commit**, cero despliegue de
código. Esta es la pieza que hace que el segundo proyecto tenga menos
fricción que el primero.

```yaml
portafolio.npc.guardian:
  clase: interactive            # interactive | batch | cpu
  engine: llm
  tenants: [org-portafolio]     # quién puede invocarla
  system_prompt_ref: guardian.md
  max_output_tokens: 200
  max_context_tokens: 1500
  max_input_chars: 1000
  temperature: 0.8
  stop: ["\nVisitante:", "</fin>"]
  peso: 1                       # cuánto descuenta del presupuesto
```

Reglas del registro:

1. **El cliente nunca manda un system prompt.** Manda `tarea` +
   valores para los huecos. Si la tarea no está en el registro, 404
   antes de tocar nada caro.
2. **El prompt vive en el repo, no en el código ni en la base.** Su
   historial de cambios es el historial de git.
3. **Nada secreto en un system prompt.** El ConfigMap lo lee cualquiera
   con lectura del cluster, y el modelo puede recitarlo.
4. **`tenants` es una lista blanca.** Una key solo invoca las tareas
   que la nombran.

---

## 7. Credenciales y sesiones

### 7.1 API key por proyecto (puerta interna)

Secret de K8s, SOPS. Se guarda el **hash SHA-256**, nunca la key.
Comparación en tiempo constante y recorrido completo de la lista sin
cortar en el primer acierto (que el tiempo de respuesta no dependa de
en qué posición está la key). Rotación: dos keys válidas a la vez
durante la ventana.

**Por qué SHA-256 pelado y no argon2/bcrypt** (el diseño decía HMAC con
pepper; al implementar quedó claro que era ceremonia sin beneficio).
Una API key de aegis no es una contraseña: son 32 bytes de
`/dev/urandom`, no algo que alguien pueda recordar ni adivinar. Los KDF
lentos existen para que un diccionario de contraseñas humanas no se
pruebe entero; contra 256 bits de entropía no hay diccionario que
probar. Y un hash rápido acá es además un requisito: verificar una key
en un endpoint sin autenticar tiene que ser barato, o el propio
verificador es el DoS (§2, corolario 1).

Formato: `aegisk_<proyecto>_<aleatorio>`. El prefijo es deliberado —
hace que una key filtrada sea **greppeable** por un escáner de
secretos. Ocultar el formato no protege nada (quien la tiene ya la
tiene) y sí impide detectar la filtración.

Dónde vive cada mitad: el **hash** en `ai-system/ai-keys`, el **claro**
en el namespace del proyecto (`org-portafolio/ai-gateway-key`), porque
rotarla es un acto del proyecto y no de la plataforma.

### 7.2 Ticket con presupuesto (puerta pública, #25)

El navegador **nunca recibe una key**: recibe una **capacidad medida**
— un ticket firmado, corto (15 min), con presupuesto embebido (20
respuestas / 6.000 tokens). Robarlo sirve de poco: viene con techo y
vencimiento. Se emite contra una prueba de humanidad enchufable
(`none` en v1, `turnstile` desde #25, por bandera del ConfigMap).

Está escrito en v1 pero **apagado**: sin Turnstile, un atacante
decidido igual consume la cuota (§12.4).

### 7.3 El historial lo guarda el gateway

Si el cliente manda el historial, el cliente controla el costo: un
script manda 12.000 tokens de "historial" y consume el máximo posible
por request, además de tirar la concurrencia a 2 (§3.1).

El gateway guarda la conversación por **`(proyecto, TAREA, sesion_id)`**,
acotada por `max_context_tokens` y con TTL. El cliente manda solo el
mensaje nuevo. **Es un cap de costo, no una comodidad.**

La **tarea** entró en la clave el 2026-08-03, después de que el humo
extremo a extremo mostrara a la guía del portafolio recordando lo que
el visitante le había preguntado al NPC Guardián con el mismo id de
sesión. Son personajes distintos y cada uno tiene que tener su propia
memoria. Y además: los caps de contexto son POR TAREA, así que un
historial compartido dejaba que una tarea de contexto chico heredara el
historial largo de otra y se pasara de su propio techo — justo el cap
que compra la concurrencia (§3.1).

`DELETE /v1/sesion/{id}` borra **todas** las conversaciones de ese
visitante, con todos los personajes: quien pide que lo olviden no está
pensando en qué tarea invocó cada vez.

Estado en memoria, sin Redis: con una réplica no hay a quién
compartírselo, y reiniciar pierde contadores — aceptable, porque
reiniciar también corta el abuso en curso.

---

## 8. Guards, capa por capa

| Capa | Frena | NO frena |
|---|---|---|
| Cloudflare (#25) | floods volumétricos, bots conocidos | un atacante paciente y lento |
| Túnel | todo lo que no venga de CF: no hay puerto abierto | — |
| Hostname propio | acopla el kill switch de la AI al del sitio | — |
| Admisión | origen, tamaño de body, content-type, tarea inexistente, ticket vencido | `Origin` forjado por un no-navegador |
| Presupuestos | granjeo sostenido (moneda = tokens) | el primer minuto de un atacante nuevo |
| Cola acotada | que un pico degrade a todos | — |
| Tarea cerrada | uso como LLM genérico | que el NPC diga una barbaridad en personaje |
| **Modo** | **todo**: réplicas 0, no hay qué abusar | — |
| K8s | cuota de GPU, PSS restricted, netpol, firma, SA sin token | — |

### 8.1 La cola es el arma principal

Bajo flood, el comportamiento correcto NO es aguantar: es **rechazar
rápido**. 4 en vuelo (el óptimo medido), 8 esperando, y todo lo demás
429 con `Retry-After` inmediato.

Una cola sin techo no protege: convierte un pico en un colapso de
latencia **para los usuarios legítimos**, que es peor que un rechazo
honesto. La posición en la cola se informa por SSE: el visitante ve
"3º en la fila", no un spinner mudo.

### 8.2 Respuesta automática al abuso

N×429 o M tokens desde una IP en una ventana → **tempban corto (5–15
min) en el gateway**. Corto a propósito: los bans largos por IP
castigan NAT compartidos, universidades y redes móviles. Los bans
permanentes viven en Cloudflare y los pone un humano.

### 8.3 Logs: nunca el contenido

Se registra: tenant, tarea, IP hasheada, tokens in/out, espera en cola,
duración, veredicto. **Nunca el prompt ni la respuesta.** Con voz
(#26) esto deja de ser higiene y pasa a ser obligación. Un modo debug
con TTL y apagado por default es el único camino para ver cuerpos, y
jamás para audio.

---

## 9. Presupuestos v1

| Límite | Valor | Por qué ese |
|---|---|---|
| En vuelo global | 4 | óptimo medido; 8 degrada latencia sin subir throughput útil |
| Cola | 8 | ~30 s de espera máxima al ritmo real |
| Salida por respuesta (NPC) | 200 tok | ~7 s de GPU; es el techo de daño de una inyección |
| Contexto por conversación | 1.500 tok | compra las 8 secuencias (§3.1) |
| Entrada del visitante | 1.000 chars | se valida en caracteres: 1000x más barato que tokenizar |
| Por IP | 600 tok salida/min | ≈5 respuestas/min: holgado para un humano, 10x lento para un script |
| Por ticket | 20 resp / 6.000 tok / 15 min | después, prueba de humanidad de nuevo |
| Timeout por request | 30 s | más que eso ya falló |

Referencia para calibrar: el techo absoluto del cluster son ~53
respuestas de NPC por minuto (6.420 tok/min ÷ ~120 tok). Una IP con
600 tok/min consume ~9% de la capacidad total.

---

## 10. Contrato HTTP

**Puerta pública :8080** — v1

```
GET /status → 200, cacheable 10 s
{"modo":"abierto","engine":"listo","cola":2,"version":"1.0.0"}
   modo:   cerrado | abierto | demo | max
   engine: apagado | calentando | listo
```

Reservado y apagado: `POST /v1/ticket`.

**Puerta interna :8081**

```
POST /v1/tarea
  Authorization: Bearer <key>
  X-Aegis-Sesion: <id opaco>
  X-Aegis-Cliente-IP: <ip del visitante final>
  {"tarea":"portafolio.npc.guardian","entrada":{"mensaje":"..."},"stream":true}
  → text/event-stream  |  application/json
  → 400 entrada inválida · 401 key · 403 tarea no permitida
  → 404 tarea inexistente · 413 body · 429 cola/presupuesto (+Retry-After)
  → 503 modo cerrado o engine no listo

GET    /v1/estado          estado extendido (cola, presupuestos, engine)
DELETE /v1/sesion/{id}     olvidar una conversación
```

---

## 11. RBAC: el gateway es CIEGO a la API de Kubernetes

El gateway es lo único alcanzable desde internet en `ai-system`. Darle
permiso para escalar Deployments es entregarle a un eventual RCE la
palanca directa sobre el cluster.

- **gateway**: SA propia, **cero permisos de API**. Lee el modo por
  volumen montado — el kubelet actualiza los ConfigMaps montados solo,
  no hace falta ni un `get`. `automountServiceAccountToken: false`.
- **controlador**: SA propia con Role **namespaced** acotado a
  `get/list/watch configmaps` y `get/patch deployments/scale` sobre
  nombres explícitos (`engine-llm`, luego `engine-media`). No escucha
  en ningún puerto público.

**Cuidado con la NetworkPolicy del controlador:** necesita egress al
apiserver, que NO es DNS ni tráfico intra-namespace. Es una regla
`ipBlock` a la IP del nodo:6443 — y esa IP ya causó un incidente
(#12, InternalIP fantasma). Va fijada, no descubierta.

---

## 12. Lo que NO se defiende (dicho de frente)

1. **La inyección de prompt no se previene, se contiene.** Alguien va
   a lograr que el NPC rompa personaje. El techo de daño es: 200
   tokens, en una burbuja de chat, sin herramientas, sin acceso a
   datos, sin poder mandar nada a ningún lado. Lo peor que pasa es una
   captura de pantalla incómoda. Blindarlo de verdad pide un
   clasificador delante y no vale la pena a esta escala.
2. **`Origin` es higiene, no control.** Un navegador lo respeta; `curl`
   pone lo que quiera. Sirve para que un sitio ajeno no consuma la
   cuota desde el navegador de un tercero, nada más.
3. **La salida del LLM es entrada NO confiable.** Si el front la
   renderiza como HTML o markdown con links, hay XSS servido por el
   propio modelo. **Se renderiza como texto plano.** Restricción para
   #24, escrita acá porque es donde se olvida.
4. **Sin Turnstile, un atacante decidido consume la cuota.** Los
   presupuestos por IP lo hacen lento y ruidoso, no imposible. Razón
   real para no dejar `max` sin vigilancia antes de #25.
5. **Una réplica es punto único de falla.** Si el gateway muere, la AI
   del sitio cae y el sitio queda perfecto porque es estático. Esa es
   exactamente la degradación buscada.

---

## 13. Modos de falla anticipados

Se anotan ANTES de que pasen; los que efectivamente muerdan se
promueven a `docs/failure-modes.md` con su clase.

- **traefik bufferea SSE.** Necesita `flushInterval: -1`. Sin eso el
  streaming llega en un bloque al final y parece que no anda nada.
- **cloudflared corta streams largos** por timeout. Se fija junto al
  hostname, en tofu.
- **`/status` como vector de DoS**: lo pega cada carga de página. Tiene
  que ser trivial, no tocar el engine, y cachearse ~10 s en CF.
- **El estado por defecto del front ante CUALQUIER error es
  "dormido"**, jamás un spinner. Gateway sin responder = mundo cerrado,
  no roto.
- **Modo abierto con engine frío = 62 s.** `/status` distingue
  `apagado`/`calentando`/`listo` para que la isla no mienta.
- **Prefijo invalidado** (§3.3): no falla nada, solo se pone 40x más
  lento el TTFT. Solo se detecta midiendo.

---

## 14. Huecos previstos

- **#25 Cloudflare**: enciende `/v1/ticket` + Turnstile por bandera;
  WAF y rate rules sobre `ai.__ROOT_DOMAIN__`; cache de `/status`.
- **#26 carril CPU**: `engine-cpu` (whisper, embeddings) NUNCA toca la
  GPU. Subir archivos es otra clase de amenaza — bombas de
  descompresión, CVEs de ffmpeg. La puerta se diseña ahora: cap de 1 MB
  / 30 s, sniffing del tipo REAL (no el declarado), cuota en **segundos
  de audio** y no en requests, transcodificado en un pod sin red.
- **engine-media** (imagen, música): excluyente con `engine-llm` por la
  cuota de GPU (bajar uno ANTES de subir el otro). Pre-generación en
  lote a Garage; jamás bajo demanda para un anónimo.
- **#27 detección**: los logs por request de §8.3 son la materia prima.

---

## 15. Invariantes (candidatos a check que muerda)

1. No existe ningún endpoint que acepte un system prompt del cliente.
2. La SA del gateway no tiene ningún permiso de API de K8s.
3. `spec.replicas` de los engines está en `ignoreDifferences` de la App.
4. Ninguna tarea del registro carece de `max_output_tokens`.
5. El gateway tiene exactamente 1 réplica declarada.
6. Ningún log de producción contiene cuerpos de request.
7. La cuota `requests.nvidia.com/gpu` del namespace sigue siendo 1.
