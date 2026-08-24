# Capacidad de AI: cuánta gente entra y por qué

Modelo para responder «¿cuántos visitantes a la vez aguanta esto?» sin
adivinar. Todos los números están **medidos** el 2026-08-16 en la máquina
de la instancia (Ryzen 9 5950X, 32 hilos, RTX 5070 de 12 GiB).

Documento hermano: [ai-gateway.md](ai-gateway.md), que cubre el carril de
GPU. Acá se cubren los dos y, sobre todo, en qué se diferencian.

---

## 1. La asimetría que gobierna todo

Los dos carriles se comportan **al revés** uno del otro, y casi todo lo
demás sale de ahí.

**La GPU es exclusiva pero AGRUPA.** vLLM hace *continuous batching*: diez
pedidos en vuelo corren de verdad juntos en la misma pasada, compartiendo
la lectura de los pesos. Medido: once traducciones salieron en 1,34 s, no
en once veces 0,2. En ese carril la concurrencia es casi gratis — diez
personas tardan casi lo mismo que una.

**La CPU es divisible pero SERIALIZA.** Whisper transcribiendo dos audios
a la vez no va el doble de rápido; comparten el ancho de banda de memoria.
Lo que se puede hacer es repartir: varios obreros con menos hilos cada uno.

Eso invierte la intuición. **La GPU, que es el recurso caro y único, es la
que mejor aguanta multitud.** Los tres modelitos de CPU, que suenan
baratos, son los que hacen cola.

---

## 2. Los números medidos

Techo de caudal por capacidad, con la configuración vigente
(`engine-cpu`: oido 4 obreros × 4 hilos, voz y vision 2 × 6):

| capacidad | 1 solo | techo | dónde satura |
|---|---|---|---|
| traduce (GPU) | ~0,2 s | **~8/s** | caché KV / presupuesto de tokens |
| vision | 0,16 s | **7,75/s** | hilos de onnxruntime |
| voz | 0,45 s | **3,36/s** | hilos de onnxruntime |
| oido | 2,67 s | **0,59/s** | obreros de CTranslate2 |
| oido, entrada patológica | 3,72 s | **0,41/s** | ídem |
| embeddings | 11 ms | **440/s** | nada que hoy importe |

`oido` es el único que está en otro orden de magnitud, y por eso es el que
manda en el modelo.

---

## 3. El modelo

Para cada capacidad *i*:

```
  λ = N · f / T          pedidos por segundo que llegan
  ρ = λ / μ              qué fracción del motor se usa
```

- **N** — visitantes a la vez en el sitio
- **f** — qué fracción de ellos está usando ESA capacidad
- **T** — segundos entre dos pedidos del mismo visitante (mirar, escribir,
  leer el resultado)
- **μ** — el techo de la tabla de arriba

Con ρ por debajo de 0,7 la espera es despreciable. Por encima de 1 la cola
crece sin fondo y no hay número que la salve.

**Los que no están medidos son `f` y `T`**, y se dice a propósito: son
supuestos sobre cómo se comporta la gente, no propiedades de la máquina.
Los de abajo son estimaciones y hay que tratarlas como tales.

| | f | T | por qué |
|---|---|---|---|
| traduce | 0,35 | 20 s | escribir una frase y leer la respuesta |
| voz | 0,25 | 25 s | escribir, sintetizar, escuchar |
| vision | 0,25 | 20 s | dar permiso, capturar, mirar las cajas |
| oido | **0,15** | **35 s** | grabar ~10 s y leer; y **mucha gente no le da el micrófono a una web** |

### El resultado para N = 50

| | λ | μ | ρ | |
|---|---|---|---|---|
| traduce | 0,88/s | 8 | **0,11** | holgado |
| vision | 0,63/s | 7,75 | **0,08** | holgado |
| voz | 0,50/s | 3,36 | **0,15** | holgado |
| oido | 0,21/s | 0,59 | **0,36** | cómodo — ~1,5 s de espera extra |

**Cincuenta entran.** El primero que se acerca al límite es `oido`, y le
sobra la mitad.

### Dónde se rompe

Despejando ρ = 0,8 para `oido`, que es el único que importa:

| si la fracción que usa oido es… | aguanta hasta |
|---|---|
| 0,15 (la estimación) | **110 visitantes** |
| 0,50 | 33 |
| 1,00 (todos grabando) | **16** |

Ese rango —de 16 a 110— **no es imprecisión del modelo: es el modelo
diciendo dónde está la incertidumbre.** No está en la máquina, está en
cuánta gente elige grabar. Si algún día hay medición real de uso, este es
el único número que hay que reemplazar.

---

## 4. El patrón: acotar el TRABAJO, no la ENTRADA

Es la lección que salió de medir, y vale para los dos carriles.

Los topes que había —300 caracteres, 8 MB, 30 segundos— acotan **lo que
entra**. Ninguno acotaba **lo que cuesta**. Medido, dos audios de la
**misma duración** (28,1 s):

| | tiempo |
|---|---|
| habla normal | 2,24 s |
| habla repetida | **10,49 s** |

Cinco veces el trabajo por el mismo tamaño de entrada. Y una cola solo
puede prometer una espera si el costo por pedido está acotado; si no, es
una cola sin unidad de medida.

La causa era la **escalera de temperaturas** de faster-whisper: ante
salida repetitiva rehace la ventana entera hasta seis veces (0.0, 0.2 …
1.0). Con `temperature=[0.0]` el peor caso baja a 2,99 s y el texto sale
igual de largo — los cinco reintentos no rescataban nada.

**Y la entrada patológica es la más probable:** lo primero que dice
cualquiera frente a un micrófono es «probando, probando».

El carril de GPU ya tenía esto resuelto sin que nos diéramos cuenta:
`max_output_tokens` por tarea acota el trabajo, no la entrada. Por eso ese
carril se comportaba y este no.

---

## 5. La trampa que casi nos come

La primera versión de la piscina **no funcionó, y no dio ningún error.**

Los endpoints eran `async def` y el trabajo de los modelos es bloqueante:
corría dentro del bucle de eventos, así que congelaba el proceso entero.
El semáforo de cuatro puestos estaba bien puesto y no protegía nada,
porque nunca había dos cosas a la vez que proteger.

Medido con la piscina «puesta»:

```
  1 a la vez    0,38/s
  4 a la vez    0,38/s
  8 a la vez    0,38/s
 16 a la vez    0,38/s     <- idéntico. Eso es serialización pura.
```

El arreglo es sacar el trabajo a un hilo de verdad
(`anyio.to_thread.run_sync`) con el `CapacityLimiter` como cupo. Los dos
hacen falta juntos: sin el hilo no hay paralelismo aunque sobren puestos,
y sin el limitador entran todos y se pisan.

**La señal que distingue es el caudal contra la concurrencia.** Una cola
que avanza se ve igual en los dos casos; lo único que los separa es que
los números no se muevan.

Antes y después, `oido` con ocho a la vez:

| | caudal | p95 |
|---|---|---|
| 1 obrero, escalera de temperaturas | 0,46/s | 18,27 s |
| piscina rota (`async def`) | 0,38/s | 20,73 s |
| **4 obreros, hilo real, sin escalera** | **0,59/s** | **13,55 s** |

---

## 6. Lo que faltaba, y qué se hizo (#95, 2026-08-17)

Los tres puntos de la primera versión de esta sección están resueltos
**en el código**; lo que falta es el tren de despliegue (abajo).

**Colas por recurso — hecho.** El gateway tiene una `Admision` por
engine (`llm` y `cpu`), el engine de la capacidad elige la cola, y cada
puerta rechaza tareas del otro carril con 400. Una transcripción ya no
puede ponerse delante de una traducción que ni usa el mismo hardware.

**Reparto justo entre inquilinos — hecho.** Al desencolar se despierta
al tenant **menos recientemente servido**, no al que llegó primero: una
ráfaga de cincuenta pedidos ya no ocupa las cincuenta primeras
posiciones. La lección de implementarlo: turnarse **exige memoria** de
a quién se acaba de servir — la primera versión recalculaba el turno
mirando solo la fila, y apenas se atendía al primero de la ráfaga el
segundo volvía a ganar por llegada. Además la sala de espera guarda un
cuarto para los demás: sin eso, «cola llena» podía significar «cola
llena DE OTRO» y la garantía de turno nunca llegaba a aplicarse.

**Admisión por costo estimado — hecho en el carril CPU.** Cada motor
del engine-cpu acota su sala (2 pedidos por obrero) y rechaza con 429 +
`Retry-After` calculado del **costo típico auto-medido** (promedio
móvil sobre lo que tardó cada pedido real). Medido: 20 pedidos
simultáneos de 27 s de audio → 12 atendidos, 8 rechazados en 66 ms con
`Retry-After: 6`.

## 6b. Dos modelos en una placa (#97, 2026-08-17)

La GPU dejó de ser «un engine»: el gateway aprende carriles de texto
como CONJUNTO (`AI_ENGINES`), cada uno con su vLLM, su
`served-model-name` y su cola del #95, y el ruteo elige carril por
capacidad. La primera convivencia:

| carril | modelo | sirve | GPU_MEM_UTIL |
|---|---|---|---|
| `llm` | Hy-MT2-1.8B bf16 | `traduccion` (traduce.exe) | 0,38 |
| `charla` | qwen3-4b-instruct-2507 AWQ int4 | `chat.rapido`, `chat.largo` | 0,38 |

El motivo es que cada modelo se quede con lo que sabe hacer: Hy-MT2 es
un traductor especialista (qwen traduciendo fallaba de dos maneras
medidas), y como conversador es al revés — el 4B narra donde el 1.8B
balbucea. La capacidad `traduccion` nació para esto: traduce.texto
nombra su promesa real y el resto del chat viajó de carril **sin tocar
ningún contrato**.

Mecánica de la convivencia: el device plugin anuncia la placa como 2
unidades (time-slicing; sin aislamiento de memoria — el reparto real lo
hacen los `gpu-memory-utilization`), la cuota de ai-system pone el
techo en 2 para que un tercer pod se rechace ruidoso, el controlador
escala la flota entera con el modo, y `VRAM_LIMITE` de `bin/ai` bajó de
4390 a 2200 (los presupuestos de los engines y el colchón del
escritorio siguen siendo una sola decisión). Agregar un tercer modelo
—la 4090 del futuro— es: pesos al PV, un Deployment calcado, una
entrada en `AI_ENGINES` y una fila en el ruteo. Cero código.

## 7. Lo que falta ahora

**El tren de despliegue llegó (2026-08-17).** Gateway `main-000013` con
las colas nuevas, engine-cpu `0.1.0-7919d8c` (imagen construida por el
job `engine-cpu` de Jenkins: kaniko → trivy → cosign, la llave nunca
salió del cluster), PVC sembrado por hardlink, y la capacidad
`embeddings` declarada al final, cuando ya se podía servir. Verificado
de punta a punta: un pod del tenant → netpol → puerta interna →
`/v1/vector` → 384d normalizados; y la tarea cpu por `/v1/tarea`
rechaza con 400.

**Medir el carril de GPU con 10 en vuelo.** El «4 es el óptimo» viene de
qwen3-4b y el motor de hoy es otro. Está anotado como pendiente en
`k8s/base/ai-system/gateway.yaml`.

**El carril CPU del laboratorio sigue local.** En el cluster el
engine-cpu solo tiene un consumidor (embeddings vía gateway); voz, oido
y vision los consume el BFF local. Llevarlos a producción es empujar
portafolio-v3, que es una decisión aparte del operador.

**postgres:17.10-alpine no re-espeja.** El build 10 de mirror-images lo
rechazó: su `gosu` upstream viene compilado con stdlib de Go 1.24.6 (7
HIGH). La copia espejada previa sigue en el registry y no tiene
consumidores desplegados; la salida es esperar el rebuild upstream o
subir a un tag que lo traiga arreglado.
