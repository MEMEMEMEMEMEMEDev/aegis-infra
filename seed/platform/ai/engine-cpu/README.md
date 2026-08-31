# engine-cpu — the AI lane that does not touch the GPU

Four capabilities that are not an LLM: synthesising speech,
transcribing it, detecting objects in an image, and embedding text.

The image is built by the `engine-cpu` job of this instance's Jenkins
(unprivileged kaniko → blocking trivy → push → cosign). The signing key
lives in a Secret of jenkins-system and never leaves the cluster.

## Why it is a separate lane

Two reasons, and neither is organisational.

**Hardware.** Behind this there is one card, and the LLM lanes live on
it with their KV cache. The models here fit in CPU with room to spare —
the largest is 82 million parameters — so putting them on the card
would compete for VRAM with the only thing that really needs it.

**Shape.** The gateway's engine lanes are a door to a text engine: they
have a task registry, conversation history and a budget in tokens. All
three stop meaning anything when what comes in is a WAV and what goes
out is a list of boxes.

## Licences: why there is no YOLO here

The Ultralytics YOLO family (v8, v10, v11) is **AGPL-3.0**, which
requires releasing anything that links it — including a service that
merely serves it over the network. RT-DETRv2 is apache-2.0, scores
better than a YOLO nano on COCO, and drags no such condition. The
decision was about the licence first and quality second; both pointed
the same way.

## The weights

They do NOT live in the repository and they do NOT travel in the image.
They go to the `modelos-cpu` PVC, and on a workstation to
`~/.cache/aegis/modelos-cpu` (or wherever `AEGIS_MODELOS_CPU` points).
`aegis ai models` is what puts them there.

Keeping them out of the image is not tidiness: it keeps the image at
~1 GB of runtime instead of 2, and — more importantly — changing a
model does not force a re-signing of the image. They are two different
life cycles.

Python **3.12** and not the latest: `onnxruntime` and `ctranslate2`
publish wheels up to 3.13. On 3.14 the install fails with an error that
looks nothing like «that version is too new».

## The numbers worth knowing

| variable | default | what it governs |
|---|---|---|
| `AEGIS_OBREROS_OIDO` | 4 | how many transcriptions at once |
| `AEGIS_OBREROS_VOZ` / `_VISION` / `_VECTOR` | 2 | the same for the others |
| `AEGIS_HILOS_OIDO` | 4 | threads per worker |
| `AEGIS_HILOS_VOZ` / `_VISION` | 6 | the same |
| `AEGIS_HILOS_VECTOR` | 4 | the same |
| `AEGIS_WHISPER` | `small` | size of the transcription model |
| `PUERTO_CPU` | 8600 | where it listens |

## The waiting room is bounded

Each engine accepts up to **2 waiting requests per worker**. With the
room full it answers 429 instantly, with `Retry-After` and a message
saying how many are ahead and how many seconds that is — instead of a
bottomless queue whose promise nobody knows. The estimate comes from the
**measured typical cost** (a moving average over what each real request
took), which starts at the values in the table below and corrects
itself.

Measured with 20 simultaneous requests of 27 s of audio: 12 served
(4 in flight + 8 in the room), 8 refused in 66 ms with `Retry-After: 6`.

`/v1/estado` publishes per engine: `en_fila`, `sala`, `espera_estimada`
and `costo_tipico`.

**The threads are per WORKER, not per engine, and the split is
measured.** With no cap, onnxruntime and CTranslate2 grab every core
they see and fight each other. But more threads per worker buys nothing
either: from 8 to 16, the time per transcription stays **the same**
(2.15 → 2.17 s). Whisper saturates much earlier — the bottleneck is
memory bandwidth, not arithmetic. Spreading them across more workers
does buy throughput.

| threads×workers | alone | throughput | p95 (8 at once) |
|---|---|---|---|
| 8 × 1 | 2.15 s | 0.46/s | 18.27 s |
| 16 × 1 | 2.17 s | 0.48/s | 17.24 s |
| 4 × 4 | 2.50 s | **0.63/s** | **12.68 s** |
| 2 × 8 | 3.61 s | 0.67/s | 11.97 s |

**4×4** was chosen over 2×8, which gives more throughput, because
whoever arrives **alone** pays 3.61 s instead of 2.50. On a site with a
single visitor at a time the normal case is one person looking, and
optimising for the crowd would charge the common case 44%.

## Input caps

| | cap |
|---|---|
| text to synthesise | 300 characters |
| audio | 8 MB and 30 seconds |
| image | 6 MB and 40 megapixels |

They are validated **before** any decoder touches the file, and by
**content**, not by extension nor by `Content-Type` — the client writes
both and neither is a statement about what the file is. A `.webm` that
is really a JPEG is refused with 415 without ever reaching PyAV.

The duration is checked at the exact point between `transcribe()` and
consuming its generator: there Whisper has already measured the audio
but has transcribed nothing yet. Checking afterwards would return a
correct 413 having done all the work anyway, which is a decorative cap.

## Measured, not assumed

On the reference machine (Ryzen 9 5950X):

| | alone | ceiling |
|---|---|---|
| synthesis | 0.45 s | 3.36/s |
| transcription (28 s of audio) | 2.67 s | 0.59/s |
| detection | 0.16 s | 7.75/s |
| embedding (1 text / batch of 16) | 11 ms / 32 ms | 440/s |
| start-up | all four models loaded in ~10 s | |

The embedding engine **verifies the quantisation on load**: two similar
sentences have to end up closer than two unrelated ones, and if int8 (or
the export) breaks that, the engine does not load. A damaged model does
not raise — it gives the wrong neighbours with total confidence.

### The temperature ladder, which was the worst problem

Two audios of the **same duration** (28.1 s) asked for very different
amounts of work:

| | by default | `temperature=[0.0]` |
|---|---|---|
| normal speech | 2.24 s | 2.09 s |
| **repeated** speech | **10.49 s** | **2.99 s** |

faster-whisper ships a ladder of retries (0.0, 0.2 … 1.0): faced with
repetitive output it redoes the **whole** window up to six times. The
text came out the same length with and without (507 against 511
characters), so the five retries rescued nothing — they only cost 3.5×.

It matters more than it looks because **the first thing anybody says in
front of a microphone is «testing, testing»**: the pathological input is
not rare, it is the most likely one.

And the heart of it: the input caps bound what **comes in**, not what it
**costs**. A queue can only promise a wait if the cost per request is
bounded.

### The pool that did not work and did not raise

The first version used `async def` with a `Semaphore`. The models' work
is blocking, so it ran on the event loop and serialised everything: the
semaphore was correctly placed and protected nothing, because there were
never two things at once to protect.

```
  1 at a time    0.38/s
  4 at a time    0.38/s
  8 at a time    0.38/s
 16 at a time    0.38/s     <- identical. Pure serialisation.
```

The fix is `anyio.to_thread.run_sync` with a `CapacityLimiter`. Both are
needed together: with no thread there is no parallelism even with seats
to spare, and with no limiter everybody comes in and treads on each
other. **The only signal that tells them apart is that throughput does
not move with concurrency.**

The round trip as proof: the speech lane synthesised «El multiverso
carga en cuatro coma dos segundos» and the hearing lane read it back as
«El multiverso carga en 4,2 segundos». That it returns the normalised
number and not the sentence that went in is the sign that it really
transcribed.

On the COCO test photo, RT-DETRv2 returned the sofa **twice** with boxes
overlapping by 99% despite advertising itself as «NMS-free». Counting
five objects where there are four is an error that does not raise, so
there is same-class overlap suppression at 0.7.

**RT-DETR does not normalise like the rest of the vision family.** Its
`preprocessor_config.json` says `do_normalize: false`: divide by 255 and
nothing else, without subtracting the ImageNet mean. Subtracting it
«because that is what one always does» would give plausible and shifted
boxes.

## The two ways to run this

**In the cluster.** The `aegis-engine-cpu` image, weights on the
`modelos-cpu` PVC, a NetworkPolicy that only lets the gateway in, and
`Recreate` because the namespace quota cannot hold two replicas at once.
The engine itself knows nothing about organizations on purpose: the
tenant, the budget and the queue live in the gateway, which is the only
thing that can reach it.

**On a workstation.** It listens on `127.0.0.1` with no credential, and
says so out loud at start-up (`el carril LOCAL: sin firma, sin cuota y
sin tenant`). Set `AEGIS_EN_CLUSTER=1` and the notice changes: a notice
claiming the wrong world sends somebody hunting for a problem that does
not exist.

## What is Spanish here, and why it was left that way

The JSON keys, the error codes and the messages this service returns are
in Spanish. They are the contract a tenant's frontend already consumes,
and translating them is a breaking change to a live integration — a
decision for the operator, not a side effect of moving this source into
the product. The prose is English; the wire was left alone, and this
section is the declaration rather than the silence.
