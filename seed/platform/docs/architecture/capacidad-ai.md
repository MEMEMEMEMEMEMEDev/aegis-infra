# AI capacity: how many people get in, and why

A model for answering «how many visitors at once does this hold?»
without guessing. Every number here was **MEASURED** on 2026-08-16 on
the instance's machine (Ryzen 9 5950X, 32 threads, RTX 5070 with
12 GiB).

Sibling document: [ai-gateway.md](ai-gateway.md), which covers the GPU
lane. Here both lanes are covered and, above all, how they differ.

---

## 1. The asymmetry that governs everything

The two lanes behave **the opposite way round** from each other, and
almost everything else follows from that.

**The GPU is exclusive but it BATCHES.** vLLM does *continuous
batching*: ten requests in flight genuinely run together in the same
pass, sharing the read of the weights. MEASURED: eleven translations
came out in 1.34 s, not in eleven times 0.2. In that lane concurrency
is nearly free — ten people take almost as long as one.

**The CPU is divisible but it SERIALIZES.** Whisper transcribing two
audio clips at once does not go twice as fast; they share memory
bandwidth. What can be done is to divide it up: several workers with
fewer threads each.

That inverts the intuition. **The GPU, which is the expensive and
single resource, is the one that best withstands a crowd.** The three
little CPU models, which sound cheap, are the ones that queue.

---

## 2. The measured numbers

Throughput ceiling per capability, with the configuration in force
(`engine-cpu`: oido 4 workers × 4 threads, voz and vision 2 × 6):

| capability | just one | ceiling | where it saturates |
|---|---|---|---|
| traduce (GPU) | ~0.2 s | **~8/s** | KV cache / token budget |
| vision | 0.16 s | **7.75/s** | onnxruntime threads |
| voz | 0.45 s | **3.36/s** | onnxruntime threads |
| oido | 2.67 s | **0.59/s** | CTranslate2 workers |
| oido, pathological input | 3.72 s | **0.41/s** | same |
| embeddings | 11 ms | **440/s** | nothing that matters today |

`oido` is the only one in a different order of magnitude, and that is
why it is the one that rules the model.

---

## 3. The model

For each capability *i*:

```
  λ = N · f / T          requests per second that arrive
  ρ = λ / μ              what fraction of the engine is in use
```

- **N** — visitors on the site at once
- **f** — what fraction of them are using THAT capability
- **T** — seconds between two requests from the same visitor (looking,
  typing, reading the result)
- **μ** — the ceiling from the table above

With ρ below 0.7 the wait is negligible. Above 1 the queue grows
bottomlessly and no number saves it.

**The ones that are NOT measured are `f` and `T`**, and that is said on
purpose: they are assumptions about how people behave, not properties
of the machine. The ones below are estimates and have to be treated as
such.

| | f | T | why |
|---|---|---|---|
| traduce | 0.35 | 20 s | type a sentence and read the answer |
| voz | 0.25 | 25 s | type, synthesize, listen |
| vision | 0.25 | 20 s | grant permission, capture, look at the boxes |
| oido | **0.15** | **35 s** | record ~10 s and read; and **plenty of people do not hand a web page their microphone** |

### The result for N = 50

| | λ | μ | ρ | |
|---|---|---|---|---|
| traduce | 0.88/s | 8 | **0.11** | roomy |
| vision | 0.63/s | 7.75 | **0.08** | roomy |
| voz | 0.50/s | 3.36 | **0.15** | roomy |
| oido | 0.21/s | 0.59 | **0.36** | comfortable — ~1.5 s of extra wait |

**Fifty get in.** The first one to come near the limit is `oido`, and
it still has half of itself to spare.

### Where it breaks

Solving ρ = 0.8 for `oido`, which is the only one that matters:

| if the fraction using oido is… | it holds up to |
|---|---|
| 0.15 (the estimate) | **110 visitors** |
| 0.50 | 33 |
| 1.00 (everybody recording) | **16** |

That range — from 16 to 110 — **is not imprecision in the model: it is
the model saying where the uncertainty lives.** It is not in the
machine, it is in how many people choose to record. If one day there is
a real measurement of usage, this is the only number that has to be
replaced.

---

## 4. The pattern: bound the WORK, not the INPUT

This is the lesson that came out of measuring, and it holds for both
lanes.

The caps that existed — 300 characters, 8 MB, 30 seconds — bound **what
comes in**. None of them bounded **what it costs**. MEASURED, two audio
clips of the **same duration** (28.1 s):

| | time |
|---|---|
| normal speech | 2.24 s |
| repetitive speech | **10.49 s** |

Five times the work for the same input size. And a queue can only
promise a wait if the cost per request is bounded; otherwise it is a
queue with no unit of measurement.

The cause was faster-whisper's **temperature ladder**: faced with
repetitive output it redoes the whole window up to six times (0.0, 0.2
… 1.0). With `temperature=[0.0]` the worst case drops to 2.99 s and the
text comes out just as long — the five retries were not rescuing
anything.

**And the pathological input is the most likely one:** the first thing
anybody says in front of a microphone is «testing, testing».

The GPU lane already had this solved without our noticing:
`max_output_tokens` per task bounds the work, not the input. That is
why that lane behaved and this one did not.

---

## 5. The trap that nearly ate us

The first version of the pool **did not work, and it raised no error at
all.**

The endpoints were `async def` and the models' work is blocking: it ran
inside the event loop, so it froze the whole process. The four-slot
semaphore was correctly placed and protected nothing, because there
were never two things at once to protect.

MEASURED with the pool «in place»:

```
  1 at a time    0.38/s
  4 at a time    0.38/s
  8 at a time    0.38/s
 16 at a time    0.38/s     <- identical. That is pure serialization.
```

The fix is to take the work out to a real thread
(`anyio.to_thread.run_sync`) with `CapacityLimiter` as the slot count.
Both are needed together: without the thread there is no parallelism
however many slots are spare, and without the limiter they all come in
and trample each other.

**The signal that tells them apart is throughput against concurrency.**
A queue that is advancing looks the same in both cases; the only thing
that separates them is that the numbers do not move.

Before and after, `oido` with eight at a time:

| | throughput | p95 |
|---|---|---|
| 1 worker, temperature ladder | 0.46/s | 18.27 s |
| broken pool (`async def`) | 0.38/s | 20.73 s |
| **4 workers, real thread, no ladder** | **0.59/s** | **13.55 s** |

---

## 6. What was missing, and what was done (#95, 2026-08-17)

The three points from the first version of this section are resolved
**in the code**; what is missing is the deployment train (below).

**Per-resource queues — done.** The gateway has one `Admision` per
engine (`llm` and `cpu`), the capability's engine picks the queue, and
each door rejects tasks from the other lane with a 400. A
transcription can no longer put itself in front of a translation that
does not even use the same hardware.

**Fair sharing between tenants — done.** On dequeuing, the tenant woken
is the **least recently served** one, not the one that arrived first: a
burst of fifty requests no longer occupies the first fifty positions.
The lesson from implementing it: taking turns **requires memory** of
who was just served — the first version recomputed the turn by looking
only at the queue, and as soon as the first of the burst had been
served the second one won again on arrival order. On top of that, the
waiting room reserves a quarter of itself for everybody else: without
that, «queue full» could mean «full OF SOMEBODY ELSE», and the
turn-taking guarantee never got a chance to apply.

**Admission by estimated cost — done in the CPU lane.** Each of
engine-cpu's motors bounds its own waiting room (2 requests per worker)
and rejects with 429 + a `Retry-After` computed from the **typical,
self-measured cost** (moving average over how long each real request
took). MEASURED: 20 simultaneous requests of 27 s of audio → 12 served,
8 rejected in 66 ms with `Retry-After: 6`.

## 6b. Two models on one card (#97, 2026-08-17)

The GPU stopped being «one engine»: the gateway learns text lanes as a
SET (`AI_ENGINES`), each with its own vLLM, its own
`served-model-name` and its own queue from #95, and the routing picks
the lane by capability. The first cohabitation:

| lane | model | serves | GPU_MEM_UTIL |
|---|---|---|---|
| `llm` | Hy-MT2-1.8B bf16 | `traduccion` (traduce.exe) | 0.38 |
| `charla` | qwen3-4b-instruct-2507 AWQ int4 | `chat.rapido`, `chat.largo` | 0.38 |

The reason is for each model to keep what it knows how to do: Hy-MT2 is
a specialist translator (qwen translating failed in two MEASURED ways),
and as a conversationalist it is the other way round — the 4B narrates
where the 1.8B babbles. The `traduccion` capability was born for this:
traduce.texto names its real promise, and the rest of the chat moved
lane **without touching any contract**.

The mechanics of the cohabitation: the device plugin advertises the
card as 2 units (time-slicing; no memory isolation — the real division
is done by the `gpu-memory-utilization` values), the ai-system quota
puts the ceiling at 2 so that a third pod is rejected loudly, the
controller scales the whole fleet with the mode, and `VRAM_LIMIT_MIB`
in `aegis ai` came down from 4390 to 2200 (the engines' budgets and the
desktop's cushion are still one single decision). Adding a third model
— the 4090 of the future — is: weights onto the PV, a Deployment traced
from the last one, an entry in `AI_ENGINES` and a row in the routing.
Zero code.

## 7. What is missing now

**The deployment train arrived (2026-08-17).** Gateway `main-000013`
with the new queues, engine-cpu `0.1.0-7919d8c` (image built by
Jenkins's `engine-cpu` job: kaniko → trivy → cosign, the key never left
the cluster), the PVC seeded by hardlink, and the `embeddings`
capability declared last, once it could already be served. Verified end
to end: a tenant pod → netpol → internal door → `/v1/vector` → 384d
normalized; and the cpu task through `/v1/tarea` is rejected with a
400.

**Measure the GPU lane with 10 in flight.** The «4 is the optimum»
comes from qwen3-4b and today's engine is a different one. It is noted
as pending in `k8s/base/ai-system/gateway.yaml`.

**The lab's CPU lane is still local.** In the cluster, engine-cpu has
only one consumer (embeddings via the gateway); voz, oido and vision
are consumed by the local BFF. Taking them to production means pushing
portafolio-v3, which is a separate decision of the operator's.

**postgres:17.10-alpine does not re-mirror.** Build 10 of mirror-images
rejected it: its upstream `gosu` comes compiled with the Go 1.24.6
stdlib (7 HIGH). The previously mirrored copy is still in the registry
and has no deployed consumers; the way out is to wait for the upstream
rebuild or to move up to a tag that brings it fixed.
