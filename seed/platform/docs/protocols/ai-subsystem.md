# Protocol — the AI subsystem

**Audience: an operator turning the AI subsystem on, or an agent
changing it.**

This file used to be the other thing entirely. Until 2026-08-29 it
opened with the machine-readable comment that declares a subsystem
missing ON PURPOSE — the one check 110 hunts for, which is why the
spelling is not repeated here: writing it again would make this
document lie about a directory the seed now ships. Its 302 lines were
an inventory of thirty-three files that lived on one running instance
and in no repository. It was a good document and it was a promise
nobody could keep: an AI lane that exists only as an inventory is an AI
lane one disk failure away from gone.

The subsystem is in the seed now. What follows is no longer how to
bring it back; it is how to switch it on, what it costs, and the
seventeen measured traps that are still traps.

---

## 0. Is this even the right machine?

The GPU lane needs a GPU. There is no way around it and no graceful
degradation: without one the engines sit `Pending` for ever and nothing
in the panel says why.

The CPU lane runs anywhere and is independent of the GPU pair. If that
is all you need, `AI=cpu` is a complete answer — the GPU engines land
scaled to zero and cost nothing.

### The minimum driver version, which used to be an open question

The previous version of this document said the minimum driver version
was **not recorded anywhere in this repository** and asked the reader to
treat it as unsolved. It is narrower now, and only as narrow as the
evidence allows.

| What is known | How it is known |
|---|---|
| The subsystem runs on the open-kernel **595.84** driver, on a 7.0 kernel | measured on the machine the lineage runs on, 2026-08-29 |
| The card is a Blackwell **consumer** part, compute capability `sm_120` | the engine images are built for `12.0` in the arch list |
| `sm_120` is enumerable from the **570** driver series onward | the CUDA 12.8 runtime, which is the oldest one PyTorch compiles `12.0` kernels for |

So phase 87 demands **570** and not 595. Demanding 595 would be writing
one machine's measurement down as everybody's requirement; demanding
nothing would be the state this table replaced. Between 570 and 595 is
**untested, not known-bad**, and the gate says so rather than pretending
either way.

There is a second, harsher fact about this class of hardware, and it is
not a software problem: a consumer card can fall off the PCIe bus under
load, which the kernel records as `Xid 79`. On the machine this was
measured on it happened five times in fourteen boots. Nothing in this
subsystem causes it and nothing in it can fix it — but if an engine dies
in a way that makes no sense, look at `dmesg` before looking at vLLM.

---

## 1. What the subsystem is

| Where | What it is |
|---|---|
| `k8s/base/ai-system/` | namespace, quota, netpols, two GPU engines, one CPU engine, gateway, mode controller, prompts, the two ksops secrets, and **two generated ConfigMaps** |
| `k8s/base/gpu/` | `RuntimeClass nvidia` + the NVIDIA device plugin, with **time-slicing** so two engines share one card |
| `k8s/argocd-apps/core.yaml` | **both** Applications — `gpu` and `ai-system` — live inside that file, not in one of their own (trap T-3) |
| `ai/engine-gpu/` | the vLLM image: Containerfile, pipeline, and its own README |
| `init/phases/87-ai.sh` | the phase that deploys it and the gates that prove it |
| `libexec/aegis-ai` | the operator's control: the mode, the images, the weights, the tenant keys |

Two files under `k8s/base/ai-system/` are **generated, not written**:
`routes.yaml` and `registro.yaml` come out of `aegis org apply`, derived
from `ai/routes.yaml`, `ai/tasks.yaml`, `plans.yaml` and the contracts.
Never hand-edit them.

`ai/aprovisionar-bucket.mjs` is **not** part of this. It lives under
`ai/` for historical reasons and belongs to the object store. Do not
assume that everything under `ai/` is AI.

---

## 2. Switching it on

Set `AI` in `aegis.conf` to `cpu` or `gpu` and run phase 87. It is
idempotent; running it on an instance that already has the subsystem
re-derives the secrets it owns and re-proves its gates.

The gates, in the order they fire, and what each one would catch:

| Gate | What it proves | What its failure means |
|---|---|---|
| `ai-images-pinned` | no image row is still on the sixty-four-zero marker | the images do not exist on this instance yet — see §3 |
| `gpu-driver-minimum` | the driver branch is at least 570 | no card, or a driver older than the architecture |
| `inotify-ceiling-for-the-device-plugin` | `fs.inotify.max_user_instances` ≥ 1024 | see T-2; this one is expensive and silent |
| `gpu-units-advertised` | the node advertises **2** units | 0 = the plugin cannot see the card; 1 = the time-slicing config did not land |
| `ai-secrets-encrypted` | both ksops files exist and decrypt | the Application would not render at all |
| `ai-pvcs-bound` | four volumes Bound | nothing has anywhere to put weights |
| `ai-gateway-responds` | the kubelet got a 200 from `/healthz` | a missing mount, the quota, or the image |
| `ai-controller-observes-the-mode` | both engines reached **zero** replicas | the strongest one — see below |

That last gate is the one to understand. The engines declare no
`replicas` field, so Kubernetes gives them 1; the controller treats an
unrecognised mode — the absent one included — as `cerrado` and takes
them to 0. Reaching zero proves the whole chain at once: the
controller's pod is up, its token is mounted, it **reached the
apiserver** (which exercises its egress NetworkPolicy), its Role really
permits `deployments/scale` on those two names, and it read the
ConfigMap. Nothing else in the phase proves any of it, and on a `gpu`
instance a failure here means a card quietly powered up.

**With `AI=no`, every one of those gates is declared WITHOUT A SUBJECT
rather than omitted.** A gate that stops being written disappears from
`gates.jsonl`, and three months later a missing line reads exactly like
a green one.

---

## 3. The images

Three, in one place — `k8s/base/ai-system/kustomization.yaml`'s
`images:` block — because the vLLM digest is referenced by three
containers and the gateway's by two, and bumping two of three leaves an
init container waiting on a server built from another commit.

| Image | Where it comes from |
|---|---|
| `aegis-ai-vllm` | built here, from `ai/engine-gpu/Containerfile` |
| `aegis-engine-cpu` | built here from `ai/engine-cpu/`, by the `engine-cpu` job |
| `ai-gateway` | mirrored into the internal registry from its own repository (gateway and controller are two binaries in one image, deliberately) |

They ship pinned to the **sixty-four-zero marker**, deliberately and
obviously false, the same convention the app templates' overlays use.
Until an image exists on THIS instance there is no digest to write.

    aegis ai images                  # what is pinned, and what the registry serves
    aegis ai images <name>:<tag>     # measure that tag's digest and write it in

`aegis ai images` also resolves the AI Containerfiles' `FROM`, which
ships as a placeholder for a reason the file explains: the mirror
rewrites the manifest as it copies, so the public digest in `images.txt`
pulls nothing here. Only the live registry knows the internal digest.

**The vLLM image is DECLARED AS NOT VERIFIED.** It has never been built
and never been run: it was written from the upstream build definitions,
not from an execution. Its README says what to watch during the first
build and what to write down afterwards. Read it before you trust it.

---

## 4. The weights

Roughly 15 GB that live in **no repository and in no backup**. The pods
have no internet egress by design and run offline explicitly, so nothing
downloads itself: a missing model produces "it is not there" instead of
a hang against a closed network.

    aegis ai models --from <directory>

`--from` is the point on a slow line: a local copy is hard-linked rather
than fetched, which is the same bytes and no extra disk. Across
filesystems it falls back to a copy, and it says which it did — a
`cp -al` that fails whole on a cross-device link is exactly the shape of
a step that reports success and does nothing.

The verification is a **size**, not an "ok". A directory that exists and
holds four bytes is the shape of an interrupted download, and it costs
an afternoon: the engine starts, loads, and dies on a truncated tensor.

**What is still owed here:** fetching them. There is no per-model
downloader in the product yet, and inventing URLs would be worse than
saying so.

---

## 5. Tenant keys

    aegis ai key issue <org>
    aegis ai key list

The key is split in two on purpose: the SHA-256 hash goes to the shared
roster (the gateway only ever needs to verify) and the cleartext to the
organization's own Secret (rotating it is the organization's act, not
the platform's). The gateway never has the cleartext stored anywhere.

The material is generated into tmpfs, read from files by everything that
touches it, and shredded on exit. It never passes through `argv`.

The shared roster is edited **entry by entry and never rewritten** — it
holds every organization's hash, so a rewrite revokes everybody. That is
precisely why no tool used to touch it.

**A key on its own is not enough**, and this is the step whose omission
fails silently:

1. the organization must appear in the `tenants` of every task it
   invokes (`registro.yaml`, regenerated by `aegis org apply` from the
   contract). Missing it: a loud 403.
2. its namespace needs an egress rule towards the internal door.
   Missing it: a **silent timeout**, which reads exactly like "the GPU
   is off".

Grant all three or none. Rotating: issue another with a different `kid`
and leave the old one in the roster until the gateway's log stops naming
it. **Removing it from the roster is the revocation, and it is a
separate act** — issuing a new key revokes nothing.

---

## 6. What is not there yet, said plainly

- **The job that builds the GPU image.** `ai/engine-gpu/Jenkinsfile`
  exists and nothing fires it: registering it is one item in
  `jenkins/values.yaml`'s job-dsl, beside the ones that are there. The
  same is true of `ai/engine-cpu/Jenkinsfile`, whose source arrived on
  2026-08-31: an image with a build definition nobody can trigger is,
  from the instance's point of view, the same as an image with no
  source at all.
- **The weight fetchers for the GPU lane.** `aegis ai models` fetches
  the CPU lane's (their URLs were measured, with their licences), and
  refuses the rest rather than guess: the GPU weights are gibibytes
  named by MODEL_ID, and transcription resolves its own by name through
  its library's cache. `--from` is the answer for both, and it is said
  out loud instead of left as a silence.
- **The seeding of the volumes, run for real.** `aegis ai seed <lane>`
  exists as of 2026-08-31 and is DECLARED NOT VERIFIED: it has never
  run against a cluster. Its first run is its verification.
- **The consumer test.** Every gate in phase 87 measures the platform
  side. The defining test is a tenant backend reaching the internal door
  with its key and getting an answer — not a 403 (missing registry
  entry) and not a timeout (missing netpol). That needs an organization
  with `ai:` in its contract, and it is owed.
- **Backups cover none of this.** The data backup tool covers database
  dumps and object buckets. Not the registry, not the AI volumes. A
  "restore from backup" step would be a lie, so there isn't one.

---

## 7. The traps

Measured, not theoretical. Each one has cost someone time.

**T-1 — `plans.yaml` must keep its `ai:` block even with no AI.** The
generator indexes it unconditionally; stripping the key raises
`KeyError`. Leaving it costs nothing.

**T-2 — The inotify ceiling is a host number, and the distro default is
a desktop one.** 128 instances starved the device plugin's file watcher
and produced **424 restarts over six days**, with the node advertising
`nvidia.com/gpu: 0` and the `gpu` Application showing *Progressing* with
all three resources *Synced*. That is the worst possible failure shape —
everything the panel inspects says yes. The host bootstrap persists
1024; phase 87's gate is what turns that written step into a measured
one.

**T-3 — Both Applications are fragments inside `core.yaml`.** Anyone
reasoning at directory granularity will miss them, and removing a
directory will not remove them.

**T-4 — The vLLM digest is referenced by three containers** and the
gateway's by two. That is why they are pinned in the kustomization's
`images:` block and not in each manifest: one row per image, and the
arithmetic cannot go wrong.

**T-5 — The gateway and the controller are one image, two binaries**,
deliberately. One pipeline, one signature, one digest to audit. The RBAC
lives on the ServiceAccount, not in the binary, which is what lets the
reachable half hold no permissions at all.

**T-6 — The VRAM threshold is DERIVED and no longer written down.** It
used to be a constant, and its history is the history of two halves of
one decision drifting apart: the engines' memory fraction moved five
times and the threshold followed late every time — once refusing a start
that fitted with 430 MiB to spare, once letting an OOM through.
`aegis ai` now computes it from the engine profiles in the repo. Moving
a fraction moves the threshold in the same commit.

**T-7 — The namespace GPU quota and the device plugin's replica count
are one decision in two files.** The quota exists so a *third* GPU pod
is rejected at admission instead of hanging `Pending` for ever. Raise
either alone and you get silent Pending.

**T-8 — The engine Deployments deliberately have no `replicas:`
field.** Writing one back makes every sync bounce both engines; the
controller re-raises them seconds later. The `ignoreDifferences` rule
does **not** prevent this.

**T-9 — `ignoreDifferences` protects the diff, not the apply.** Measured
twice: a sync reverted the mode ConfigMap in under ten seconds and the
controller scaled the GPU down behind it, with the app showing Synced
throughout. The only thing that works is **git not declaring the field
at all**, which is why the mode ConfigMap ships with no `data:` block.
That apparent omission is the mechanism. Do not "fix" it.

**T-10 — In `ignoreDifferences`, `group` must be *absent*, not empty.**
The API server drops an empty string on read, so git and the live object
disagree for ever. This is the opposite of the AppProject blacklist,
where the empty string is correct.

**T-11 — No node address is hardcoded any more, and that is a trade.**
The lineage pinned the node's InternalIP in one NetworkPolicy, where it
appeared exactly once in the whole tree, so nothing could flag a
mismatch; on a different node the controller simply logged that it could
not read the mode. The product cannot carry one machine's address, so
the rule now names the three private ranges. **A node whose InternalIP
is PUBLIC is not covered** — and that does not fail silently any more,
because `ai-controller-observes-the-mode` exercises exactly that path.
The remedy is one more `ipBlock` in the instance's own tree.

**T-12 — Prompt prefixes must be byte-stable.** The engines' prefix
cache takes time-to-first-token from ~1000 ms to ~25 ms. Inserting a
date, a visitor name or a counter invalidates it on **every** request,
with no error — just forty times slower. It is the easiest mistake to
make and the hardest to notice.

**T-13 — The in-flight limit and the engine's sequence limit must say
the same number.** They do, in both lanes, and check 159 keeps them
equal. With the gateway at 10 and an engine at 8, two requests would
wait *inside* the engine instead of in the queue: nothing breaks, but
the number stops meaning what it says and the queue stops being the only
place where anyone waits.

**T-14 — `sops -d <file> | head -c 1 && echo ok` lies.** The `&&` still
short-circuits true when `head` reads the first byte of a *stderr
failure message*. Validate by exit code. It is this repo's canonical
example of a reading that lies.

**T-15 — `SOPS_AGE_KEY_FILE` must be set explicitly.** This instance's
identity is not the file sops defaults to. Omitting it fails with a
misleading "no such file or directory" even though the key exists.

**T-16 — Rotating a tenant key does not revoke the old one.** §5.

**T-17 — The CPU engine's `Recreate` strategy cannot be applied to a
Deployment that was born `RollingUpdate`.** Strategic merge will not drop
the `rollingUpdate` block and kustomize prunes the null that would. Born
fresh it is fine; converting a half-restored one is not. The manifest
here is born fresh.

---

## 8. How to know you are done

Not "the pods are green". The subsystem is on when:

1. the node advertises `nvidia.com/gpu: 2` (on a `gpu` instance);
2. `ai-controller-observes-the-mode` passed, which is the engines
   reaching zero;
3. `aegis ai status` reports the mode, both engines and the VRAM;
4. a tenant backend reaches the internal gateway with its key and gets
   an answer — not a 403 and not a timeout;
5. `aegis org apply` regenerates the two derived ConfigMaps with no diff.

Point 4 is owed (§6). If any of the five is unverified, **say so** rather
than declaring the subsystem on. An AI lane that is half-wired fails
silently, in production, at the worst moment — which is the whole reason
this file exists.
