# ai-gateway — design

THE canonical source for the multi-project AI substrate. If this
document and the code diverge, IT IS A BUG: they get fixed together.

Status: design closed 2026-08-02. Implementation under way (#23).
It precedes #24 (the portfolio consumes it), #25 (Cloudflare),
#26 (CPU lane).

---

## 1. What it is, and above all what it is NOT

The gateway is **the only door** between any client and the
cluster's single GPU. Projects do not run AI in their own
namespaces: they talk to the gateway over HTTP.

What it is NOT, and is never going to be:

- **It is not an LLM proxy.** There is no endpoint that accepts a
  free-form prompt, and there never will be. The client picks a
  **task from the registry** and fills in the blanks. The day a
  `/chat` with an arbitrary prompt exists, you have stopped having
  an AI service and you have a free OpenAI proxy with your name on
  the DNS.
- **It is not highly available.** One GPU = one replica. Two
  replicas do not buy availability, they buy two quota counters
  that do not talk to each other.
- **It does not start by itself.** Nothing turns the GPU on except
  the operator. The automation only SHUTS DOWN (§5).

---

## 2. The asymmetry that governs everything

A `POST` costs the attacker ~0 and costs **between 2 and 7 seconds
of GPU**. This is not an API where the ceiling is CPU and abuse is
paid for on the invoice: here the ceiling is physical, there is
exactly one of it, and it is the same card the operator works on.

Corollaries that apply throughout the design:

1. **Rejecting has to be cheap.** If validating costs the same as
   serving, the guard IS the DoS. Hence the order of the filters:
   whatever discards most for least, first (body size before
   reading the whole body; characters before tokens; a
   non-existent task before a budget).
2. **The currency is the token, not the request.** 10 requests of
   20 tokens and 10 of 2,000 are not the same consumption. Budgets
   are kept in output tokens.
3. **The asset to protect is the operator's machine**, not an
   invoice. Successful abuse does not cost money: it costs being
   able to use the computer.

---

## 3. The numbers that size the guards

MEASURED on bare metal (`aegis-exploration/mediciones`,
2026-07-25) and confirmed in the cluster (2026-07-30). These are
not estimates.

| Quantity | Value |
|---|---|
| Aggregate throughput, concurrency 4 | **107 tok/s** = 6,420 tok/min |
| TTFT cold / with a cached prefix | <1 s / **25 ms** |
| Engine startup (warm cache) | **62 s** |
| 40-token response, warm | 565–584 ms |
| VRAM with the model loaded | 10.7 / 12.2 GB |
| Real KV cache in the cluster | **27,840 tokens** |
| KV cache with clean VRAM | 35,616 tokens |

### 3.1 The concurrency ceiling is not `max_num_seqs`

`max_model_len` is 12,288 and the measured KV cache was 27,840
tokens:

```
27,840 / 12,288 = 2.26 simultaneous conversations
```

With a full context **8 sequences do not fit, 2 do**. The
profile's `max_num_seqs: 8` is an aspiration that only holds if
every conversation is short:

| Context per conversation | Sequences that fit |
|---|---|
| 12,288 (maximum) | 2 |
| 4,000 | 6 |
| 2,000 | 8 (capped by max_num_seqs) |

**Design consequence:** the per-task context cap is not
stinginess, it is **what buys the concurrency**. An NPC with 1,500
tokens of context allows 8 simultaneous visitors; the same NPC
with unbounded history allows 2. That is why the history belongs
to the gateway and not to the client (§7.3).

### 3.2 Streaming is mandatory, not a luxury

107 tok/s split across 4 streams = ~27 tok/s per stream. A
200-token response takes ~7.5 s to complete. Without streaming
that is a 7-second spinner and it looks broken. With streaming,
the first token lands in <1 s and 27 tok/s runs faster than
anybody reads (~7 tok/s).

### 3.3 The prefix cache dictates the ORDER of the prompt

TTFT drops to 25 ms with a cached prefix: 40x. That imposes a hard
rule:

> Every task's system prompt is **byte-for-byte identical** on
> every request and goes **first**. The variable data (visitor's
> name, time of day, history) ALWAYS goes at the end.

Putting anything variable above the prompt invalidates the prefix
and multiplies TTFT by 40. It is the easiest mistake to make and
the hardest to notice: nothing fails, it just gets slow.

---

## 4. Topology

```
                    ┌──────────────────── ai-system ────────────────────┐
                    │                                                   │
browser             │   ai-gateway                        engine-llm    │
   │                │   ┌──────────────┐                 ┌───────────┐  │
   ├─▶ portafolio.  │   │              │                 │  vLLM     │  │
   │   __ROOT_DOMAIN__ │   │  :8081  ─────┼────────────────▶│  :8000    │  │
   │      │         │   │  internal    │                 │  0 ↔ 1    │  │
   │      ▼         │   │              │                 └───────────┘  │
   │   BFF (Express)├──▶│              │                       ▲        │
   │   org-portaf.  │   │  :8080       │                       │        │
   │   [API key]    │   │  public      │                 ai-modo-       │
   │                │   │  v1: /status │                 controller     │
   └─▶ ai.<domain>  ├──▶│  only        │                 [minimal RBAC] │
                    │   └──────┬───────┘                       ▲        │
                    │          │ reads (mounted volume)        │ watches│
                    │          └────────  ConfigMap ai-modo ───┘        │
                    └───────────────────────────────────────────────────┘
                                          ▲
                                          │ writes
                                    `aegis ai` CLI  (on the operator's machine)
```

### 4.1 Two physically distinct doors

| | :8080 public | :8081 internal |
|---|---|---|
| Who arrives | traefik ← tunnel ← Cloudflare | named tenant namespaces |
| Credential | budgeted ticket (#25) | the project's API key |
| CF headers | trusted | **ignored** |
| v1 serves | only `GET /status` | everything |

Two **ports** and not two routes, because that way **the
NetworkPolicy can force each origin onto its own**. Without it, a
compromised tenant pod could send a forged `CF-Connecting-IP` and
pass itself off as public traffic; or a visitor could try the
internal route. With two ports, the separation is imposed by the
kernel and not by an `if` in the code.

### 4.2 Why the public door is born almost empty

In v1 inference is **not reachable from the internet**. The
browser goes through the BFF, which holds the key server-side.
`ai.__ROOT_DOMAIN__` exists anyway because:

- it gives a kill switch and WAF rules **independent of the
  portfolio** — the AI is switched off and the site is untouched;
- it gives #25 a target to bind to;
- it exercises the whole edge path before putting anything
  expensive behind it;
- it is a health check from outside the cluster.

The only thing it serves is an ~80-byte JSON, cacheable for 10 s.
Everything else answers 404. The ticket endpoint is **written and
switched off** by a flag; #25 turns it on without touching code.

### 4.3 One image, two binaries, two ServiceAccounts

`cmd/gateway` and `cmd/controller` come out of the same repo and
the SAME signed image. They are two Deployments with a different
`command` and different accounts: **the RBAC lives in the
ServiceAccount, not in the binary**. It saves an entire pipeline
without weakening the separation of §11.

---

## 5. The mode: the single source of truth

One ConfigMap, `ai-modo`, in `ai-system`. The `aegis ai` CLI
writes it, the controller watches it, the gateway reads it through
a mounted volume.

```yaml
modo: cerrado          # cerrado | abierto | demo | max
vence: ""              # RFC3339, only in demo
motivo: "playing"      # free text, for the operator
actualizado: "2026-08-02T14:03:11Z"
```

| Mode | engine | Budgets | Expiry |
|---|---|---|---|
| `cerrado` | 0 | — (503, asleep) | — |
| `abierto` | 1 | normal | none |
| `demo` | 1 | wide | **60 min, closes itself** |
| `max` | 1 | wide | none (requires #25) |

### 5.1 The automation only SHUTS DOWN

Hard rule, no exceptions: **nothing turns the GPU on except the
operator**. What automation does exist:

- expiry of `demo` → `cerrado`;
- an optional closing time → `cerrado`;
- (future) a sustained error rate → `cerrado`.

There is no auto-open, there is no "turn on on demand", there is
no scale-from-zero per request. If somebody enters the portfolio
at 4 AM they see the world asleep, and that is correct.

### 5.2 The dirty-VRAM preflight is done by the CLI

Starting the engine with the desktop occupying VRAM **cuts the KV
cache permanently** until it is restarted (35,616 → 27,840 tokens
MEASURED, −22%), and with it halves the real concurrency.

The check does NOT go in the cluster: it goes in the CLI, which
runs on the operator's machine, where `nvidia-smi` really exists.
`aegis ai open` looks at the free VRAM, and if it is dirty it
**refuses** and says which process is holding it. `--force` exists
for whoever knows what they are doing.

Zero complexity inside the cluster for a problem that lives
outside it.

### 5.2.1 The CLI

It lives in `libexec/aegis-ai`, is reached as `aegis ai`, and is
the ONLY thing that turns anything on. It writes the ConfigMap and
nothing else: it does not scale, it does not touch pods, it does
not talk to the gateway.

```
aegis ai status                what is happening right now
aegis ai open [--until HH:MM]  turns on (checks the VRAM first)
aegis ai demo [minutes]        wide + TTL, default 60 min, self-closing
aegis ai max [--until HH:MM]   wide, without a TTL
aegis ai stop [reason]         turns off
aegis ai logs [-f] / aegis ai engine-logs
```

`--until` and the `demo` TTL write the SAME `vence` field: one
single mechanism for a demo's expiry and for a scheduled close. It
avoids depending on tzdata, which a `FROM scratch` image does not
have.

### 5.3 The kill switch works with the gateway dead

The CLI writes the ConfigMap; the controller scales. The gateway
takes no part. If the gateway is hung, `aegis ai stop` still turns
the GPU off. And if the controller is down too, `kubectl scale`
remains — which ArgoCD does not revert, because `spec.replicas` is
in `ignoreDifferences`.

---

## 6. The task registry

One ConfigMap. Adding an NPC is **one commit**, zero code
deployment. This is the piece that makes the second project less
friction than the first.

```yaml
portafolio.npc.guardian:
  clase: interactive            # interactive | batch | cpu
  engine: llm
  tenants: [org-portafolio]     # who may invoke it
  system_prompt_ref: guardian.md
  max_output_tokens: 200
  max_context_tokens: 1500
  max_input_chars: 1000
  temperature: 0.8
  stop: ["\nVisitante:", "</fin>"]
  peso: 1                       # how much it draws from the budget
```

Registry rules:

1. **The client never sends a system prompt.** It sends `tarea` +
   values for the blanks. If the task is not in the registry: 404,
   before touching anything expensive.
2. **The prompt lives in the repo, not in the code and not in a
   database.** Its change history is git's history.
3. **Nothing secret in a system prompt.** Anyone with read access
   to the cluster reads the ConfigMap, and the model can recite
   it.
4. **`tenants` is an allowlist.** A key only invokes the tasks
   that name it.

---

## 7. Credentials and sessions

### 7.1 One API key per project (internal door)

A K8s Secret, SOPS. What is stored is the **SHA-256 hash**, never
the key. Constant-time comparison and a full walk of the list
without short-circuiting on the first hit (so that response time
does not depend on where in the list the key sits). Rotation: two
keys valid at once during the window.

**Why bare SHA-256 and not argon2/bcrypt** (the design said HMAC
with a pepper; on implementing it, it was clear that this was
ceremony without benefit). An aegis API key is not a password: it
is 32 bytes out of `/dev/urandom`, not something anyone can
remember or guess. Slow KDFs exist so that a dictionary of human
passwords cannot be tried in full; against 256 bits of entropy
there is no dictionary to try. And a fast hash here is a
requirement besides: verifying a key on an unauthenticated
endpoint has to be cheap, or the verifier itself is the DoS (§2,
corollary 1).

Format: `aegisk_<proyecto>_<aleatorio>`. The prefix is deliberate
— it makes a leaked key **greppable** by a secret scanner. Hiding
the format protects nothing (whoever has it already has it) and
does prevent the leak from being detected.

Where each half lives: the **hash** in `ai-system/ai-keys`, the
**cleartext** in the project's namespace
(`org-portafolio/ai-gateway-key`), because rotating it is an act
of the project and not of the platform.

### 7.2 Budgeted ticket (public door, #25)

The browser **never receives a key**: it receives a **measured
capability** — a signed, short-lived ticket (15 min) with the
budget embedded (20 responses / 6,000 tokens). Stealing it is
worth little: it comes with a ceiling and an expiry. It is issued
against a pluggable proof of humanity (`none` in v1, `turnstile`
from #25 on, by a ConfigMap flag).

It is written in v1 but **switched off**: without Turnstile, a
determined attacker consumes the quota anyway (§12.4).

### 7.3 The gateway is what keeps the history

If the client sends the history, the client controls the cost: a
script sends 12,000 tokens of "history" and consumes the maximum
possible per request, on top of dropping the concurrency to 2
(§3.1).

The gateway keys the conversation by
**`(proyecto, TAREA, sesion_id)`**, bounded by
`max_context_tokens` and with a TTL. The client sends only the new
message. **It is a cost cap, not a convenience.**

The **task** entered the key on 2026-08-03, after the end-to-end
smoke test showed the portfolio's guide remembering what the
visitor had asked the Guardian NPC under the same session id. They
are different characters and each one has to have its own memory.
And on top of that: the context caps are PER TASK, so a shared
history let a small-context task inherit another one's long
history and blow past its own ceiling — precisely the cap that
buys the concurrency (§3.1).

`DELETE /v1/sesion/{id}` erases **all** of that visitor's
conversations, with every character: whoever asks to be forgotten
is not thinking about which task they invoked each time.

State in memory, no Redis: with one replica there is nobody to
share it with, and restarting loses counters — acceptable, because
restarting also cuts off the abuse in progress.

---

## 8. Guards, layer by layer

| Layer | Stops | Does NOT stop |
|---|---|---|
| Cloudflare (#25) | volumetric floods, known bots | a patient, slow attacker |
| Tunnel | anything not coming from CF: there is no open port | — |
| Its own hostname | the AI's kill switch being tied to the site's | — |
| Admission | origin, body size, content-type, non-existent task, expired ticket | an `Origin` forged by a non-browser |
| Budgets | sustained farming (currency = tokens) | a new attacker's first minute |
| Bounded queue | one spike degrading everybody | — |
| Closed task | use as a generic LLM | the NPC saying something outrageous, in character |
| **Mode** | **everything**: 0 replicas, there is nothing to abuse | — |
| K8s | GPU quota, PSS restricted, netpol, signature, SA without a token | — |

### 8.1 The queue is the main weapon

Under a flood the correct behaviour is NOT to endure: it is to
**reject fast**. 4 in flight (the MEASURED optimum), 8 waiting,
and everything else 429 with an immediate `Retry-After`.

An unbounded queue does not protect: it turns a spike into a
latency collapse **for the legitimate users**, which is worse than
an honest rejection. Queue position is reported over SSE: the
visitor sees "3rd in line", not a mute spinner.

### 8.2 Automatic response to abuse

N×429 or M tokens from one IP within a window → **a short tempban
(5–15 min) in the gateway**. Short on purpose: long per-IP bans
punish shared NATs, universities and mobile networks. Permanent
bans live in Cloudflare and a human puts them there.

### 8.3 Logs: never the content

What is recorded: tenant, task, hashed IP, tokens in/out, queue
wait, duration, verdict. **Never the prompt and never the
response.** With voice (#26) this stops being hygiene and becomes
an obligation. A debug mode with a TTL, off by default, is the
only path to seeing bodies — and never for audio.

---

## 9. v1 budgets

| Limit | Value | Why that one |
|---|---|---|
| Global in flight | 4 | MEASURED optimum; 8 degrades latency without raising useful throughput |
| Queue | 8 | ~30 s of maximum wait at the real rate |
| Output per response (NPC) | 200 tok | ~7 s of GPU; it is the damage ceiling of an injection |
| Context per conversation | 1,500 tok | buys the 8 sequences (§3.1) |
| Visitor input | 1,000 chars | validated in characters: 1000x cheaper than tokenizing |
| Per IP | 600 output tok/min | ≈5 responses/min: roomy for a human, 10x slow for a script |
| Per ticket | 20 resp / 6,000 tok / 15 min | after that, proof of humanity again |
| Timeout per request | 30 s | anything longer has already failed |

Reference for calibration: the cluster's absolute ceiling is ~53
NPC responses per minute (6,420 tok/min ÷ ~120 tok). One IP at 600
tok/min consumes ~9% of the total capacity.

---

## 10. HTTP contract

**Public door :8080** — v1

```
GET /status → 200, cacheable 10 s
{"modo":"abierto","engine":"listo","cola":2,"version":"1.0.0"}
   modo:   cerrado | abierto | demo | max
   engine: apagado | calentando | listo
```

Reserved and switched off: `POST /v1/ticket`.

**Internal door :8081**

```
POST /v1/tarea
  Authorization: Bearer <key>
  X-Aegis-Sesion: <opaque id>
  X-Aegis-Cliente-IP: <ip of the end visitor>
  {"tarea":"portafolio.npc.guardian","entrada":{"mensaje":"..."},"stream":true}
  → text/event-stream  |  application/json
  → 400 invalid input · 401 key · 403 task not permitted
  → 404 task does not exist · 413 body · 429 queue/budget (+Retry-After)
  → 503 mode cerrado, or engine not ready

GET    /v1/estado          extended state (queue, budgets, engine)
DELETE /v1/sesion/{id}     forget a conversation
```

---

## 11. RBAC: the gateway is BLIND to the Kubernetes API

The gateway is the only thing reachable from the internet in
`ai-system`. Giving it permission to scale Deployments hands an
eventual RCE the direct lever over the cluster.

- **gateway**: its own SA, **zero API permissions**. It reads the
  mode from a mounted volume — the kubelet refreshes mounted
  ConfigMaps by itself, not even a `get` is needed.
  `automountServiceAccountToken: false`.
- **controller**: its own SA with a **namespaced** Role scoped to
  `get/list/watch configmaps` and `get/patch deployments/scale`
  over explicit names (`engine-llm`, later `engine-media`). It
  listens on no public port.

**Careful with the controller's NetworkPolicy:** it needs egress
to the apiserver, which is NOT DNS and is not intra-namespace
traffic. It is an `ipBlock` rule to the node's IP:6443 — and that
IP has already caused one incident (#12, phantom InternalIP). It
is pinned, not discovered.

---

## 12. What is NOT defended (said to your face)

1. **Prompt injection is not prevented, it is contained.**
   Somebody is going to get the NPC to break character. The damage
   ceiling is: 200 tokens, in a chat bubble, with no tools, no
   access to data, unable to send anything anywhere. The worst
   that happens is an awkward screenshot. Armouring it for real
   asks for a classifier in front, and it is not worth it at this
   scale.
2. **`Origin` is hygiene, not control.** A browser honours it;
   `curl` puts whatever it likes. It is good for keeping somebody
   else's site from consuming the quota out of a third party's
   browser, nothing more.
3. **The LLM's output is UNTRUSTED input.** If the front end
   renders it as HTML, or as markdown with links, there is XSS
   served by the model itself. **It is rendered as plain text.** A
   constraint for #24, written here because this is where it gets
   forgotten.
4. **Without Turnstile, a determined attacker consumes the
   quota.** The per-IP budgets make it slow and noisy, not
   impossible. The real reason not to leave `max` unwatched before
   #25.
5. **One replica is a single point of failure.** If the gateway
   dies, the site's AI goes down and the site stays perfect,
   because it is static. That is exactly the degradation being
   aimed for.

---

## 13. Anticipated failure modes

They are written down BEFORE they happen; the ones that actually
bite get promoted to `docs/failure-modes.md` with their class.

- **traefik buffers SSE.** It needs `flushInterval: -1`. Without
  that, the stream arrives as one block at the end and it looks
  like nothing works.
- **cloudflared cuts long streams** on timeout. It is set
  alongside the hostname, in tofu.
- **`/status` as a DoS vector**: every page load hits it. It has
  to be trivial, it must not touch the engine, and it must be
  cached ~10 s at CF.
- **The front end's default state on ANY error is "asleep"**,
  never a spinner. A gateway that does not answer = a closed
  world, not a broken one.
- **Mode `abierto` with a cold engine = 62 s.** `/status`
  distinguishes `apagado`/`calentando`/`listo` so that the island
  does not lie.
- **Invalidated prefix** (§3.3): nothing fails, TTFT just gets 40x
  slower. It is only detected by measuring.

---

## 14. Planned gaps

- **#25 Cloudflare**: turns on `/v1/ticket` + Turnstile by flag;
  WAF and rate rules over `ai.__ROOT_DOMAIN__`; caching of
  `/status`.
- **#26 CPU lane**: `engine-cpu` (whisper, embeddings) NEVER
  touches the GPU. Uploading files is another class of threat —
  decompression bombs, ffmpeg CVEs. The door is designed now: a
  cap of 1 MB / 30 s, sniffing of the REAL type (not the declared
  one), quota in **seconds of audio** and not in requests,
  transcoding in a pod with no network.
- **engine-media** (image, music): mutually exclusive with
  `engine-llm` because of the GPU quota (bring one down BEFORE
  bringing the other up). Batch pre-generation into Garage; never
  on demand for an anonymous visitor.
- **#27 detection**: the per-request logs of §8.3 are the raw
  material.

---

## 15. Invariants (candidates for a check with teeth)

1. There is no endpoint that accepts a system prompt from the client.
2. The gateway's SA has no K8s API permission at all.
3. The engines' `spec.replicas` is in the App's `ignoreDifferences`.
4. No task in the registry lacks `max_output_tokens`.
5. The gateway has exactly 1 declared replica.
6. No production log contains request bodies.
7. The namespace's `requests.nvidia.com/gpu` quota is still 1.
