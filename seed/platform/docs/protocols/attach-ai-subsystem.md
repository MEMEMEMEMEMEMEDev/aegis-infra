<!-- aegis-absent: k8s/base/ai-system -->
<!-- This line is not decoration. It is the machine-readable
     declaration that the subsystem below is missing ON PURPOSE.
     `aegis verify` fails if a directory the generator can write
     to is absent without one of these, and it fails just as hard
     if one of these names something that is actually present. -->

# Protocol — attaching the AI subsystem

**Audience: an agent, or an operator, bringing the AI subsystem onto a
running aegis instance that does not have it.**

This seed ships aegis **without AI**. Three design documents travel with
it — `architecture/ai-gateway.md`, `architecture/capacidad-ai.md`, and
`protocols/ai-tenant-key.md` — but no manifests, no images, no engine
code. That is deliberate, and this file is the other half of that
decision: the AI subsystem is *absent by declaration*, not by oversight,
and this is the document that makes the difference visible.

Read this in full before you touch anything. It is written from a
measured inventory of a working instance, not from memory, and most of
it is the parts that bite.

---

## 0. Before anything: is this even the right machine?

The GPU lane needs a GPU. There is no way around it and no graceful
degradation: without one the engines sit `Pending` forever and nothing
in the panel says why.

    kubectl get node <node> -o jsonpath='{.status.allocatable}'

If that output has no `nvidia.com/gpu` key, stop and read §4 first.

The CPU lane (`engine-cpu`: speech, transcription, embeddings, vision)
runs anywhere and is independent of the GPU pair. If all you need is
the CPU lane, you can do steps 1, 2, 6, 7, 9, 10, 11, 12 and skip the
rest.

---

## 1. What "the AI subsystem" actually is

Thirty-three files across five places. The count matters: if you bring
back thirty of them the thing comes up and misbehaves quietly.

| Where | Files | What it is |
|---|---|---|
| `k8s/base/ai-system/` | 14 | namespace, quota, netpols, two GPU engines, one CPU engine, gateway, mode controller, prompts, two encrypted secrets, and **two generated ConfigMaps** |
| `k8s/base/gpu/` | 3 | `RuntimeClass nvidia` + the NVIDIA device plugin DaemonSet, with **time-slicing** so two engines share one card |
| `k8s/argocd-apps/ai.yaml` | 1 | the Application that delivers `ai-system` |
| `k8s/argocd-apps/core.yaml` | *a fragment* | the `gpu` Application lives **inside** `core.yaml`, not in its own file — see trap T-3 |
| `ai/engine-cpu/` | 8 | the CPU lane: FastAPI server, Containerfile, Jenkinsfile, model fetcher |
| `bin/ai` | 1 | the operator's on/off switch |

Two of those files are **generated, not written**: `ai-system/routes.yaml`
and `ai-system/registro.yaml` come out of `aegis org apply`, derived from
`ai/routes.yaml`, `ai/tasks.yaml`, `plans.yaml` and the org contracts.
Never hand-edit them; regenerate them (step 11).

**`ai/aprovisionar-bucket.mjs` is not part of this.** It lives under
`ai/` for historical reasons and belongs to **Garage**: the generator
reads it and embeds it in the bucket-provisioning Job. It already ships
in this seed. Do not move it, and do not assume that everything under
`ai/` is AI.

---

## 2. What is NOT in any repository

This is the part a protocol usually gets wrong, so it comes before the
steps rather than after.

**Model weights — roughly 14 GB, in no repo and in no backup.** They are
seeded into the PVCs **by hand from the host**, with `cp -al` (hardlinks,
no extra disk). The pods have no internet egress by design and run with
`HF_HUB_OFFLINE=1`, so nothing downloads itself. `ai/engine-cpu/traer-modelos.sh`
fetches the CPU-lane weights; **there is no equivalent script for the two
GPU models** — that is a real hole, not an omission in this document.

**Container images — three, and one of them has no build pipeline.**
`aegis-engine-cpu` is rebuildable from `ai/engine-cpu/Jenkinsfile`. The
gateway image comes from a separate repository. The vLLM image
(`aegis-ai-vllm`) was hand-assembled in a ceremony that was explicitly
dismantled and recorded as **not reproducible from the internet**: it is
a frozen virtualenv packaged as OCI layers. If the internal registry is
lost and that virtualenv is lost, both GPU engines are unrecoverable
without redoing that work from scratch.

**Backups do not cover any of this.** The data backup tool covers
postgres dumps and Garage buckets. Not the registry, not the AI PVCs.
A "restore from backup" step would be a lie, so there isn't one.

**Tenant API keys** are issued by a manual ceremony — see
`protocols/ai-tenant-key.md`. The clear half goes into the tenant's
namespace; only a SHA-256 hash goes into the shared `ai-keys` secret.
That shared file is **shared across all organizations**, which is why no
tool edits it automatically: a mistyped onboarding would overwrite
another tenant's entry.

---

## 3. Order of attachment

Each step names what makes it verifiable. A step without a passing check
is a step that did not happen.

**1 — Host: NVIDIA driver and container toolkit, then restart k3s.**
k3s scans `$PATH` for `nvidia-container-runtime` **at boot only** and
regenerates its containerd config from a template each start. Installing
the toolkit without restarting k3s leaves pods stuck in
`ContainerCreating` with `no runtime for "nvidia" is configured`.
*Verify:* `nvidia-smi` prints a table, and the generated containerd
config mentions `nvidia`.

> The minimum driver version is **not recorded anywhere in this
> repository**. The card this was measured on is Blackwell (`sm_120`),
> which constrains it, but no document states a number. Treat this as an
> open question, not a solved one.

**2 — Host: the inotify ceiling.** Re-run `ansible/playbooks/bootstrap-host.yml`,
which persists `fs.inotify.max_user_instances=1024` to
`/etc/sysctl.d/99-aegis-k3s.conf`. The distro default of 128 is a desktop
number: it starved the device plugin's file watcher and produced **424
restarts over six days**, with the node advertising `nvidia.com/gpu: 0`
and the `gpu` Application showing *Progressing* with all three resources
*Synced*. That is the worst possible failure shape — everything the
panel inspects says yes.
*Verify:* `sysctl fs.inotify.max_user_instances` → `1024`.

**3 — Registry: the three images must resolve by digest.** Everything
below pulls from the internal registry by digest, not tag.
*Verify:* `crane digest` resolves each of the three.

**4 — Sync `kyverno-policies` before anything else.** The `ai-system`
namespace is born carrying the tenant enforcement label, so there must
be no window in which it admits unsigned pods.
*Verify:* the signature ClusterPolicy exists and is in enforcing mode.

**5 — Add the `gpu` Application to `core.yaml` and sync it.** This must
precede any GPU pod.
*Verify:* `kubectl get node <node> -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'`
returns **2**, not 1. Two is the time-sliced count. One means the plugin
registered but the slicing config did not.

**6 — Secrets.** Restore the age key, then issue tenant keys per
`protocols/ai-tenant-key.md`. The ksops generator is an explicit list,
not a glob: both encrypted files must exist and decrypt before the
Application can render.
*Verify:* see trap T-14 — the obvious one-liner lies.

**7 — Add `k8s/base/ai-system/` and `k8s/argocd-apps/ai.yaml`; sync.**
Namespace, quota, service account, secrets, PVCs and netpols land.
*Verify:* four PVCs `Bound`.

**8 — Seed the weights into the PVCs from the host.** Nothing downloads
itself; see §2.
*Verify:* the CPU engine lists its four model directories; for the GPU
engines, reaching `Ready` at all is the proof.

**9 — Bring up `engine-llm` first, then `engine-charla`.** Not a
preference — an ordering constraint. Both vLLM processes compute their
KV cache by measuring **free** VRAM at startup, so starting together
makes both of them count memory the other is about to take:

    Available KV cache memory: -2.94 GiB   ->  CrashLoopBackOff

It resolved itself on the second or third restart, when one won the race
and the other measured against a settled number. That is not starting —
that is getting lucky, with two wasted minutes and a crash in the log
that was not the model's fault. `engine-charla` now carries an
initContainer that waits for `engine-llm` to serve, capped at ten
minutes.
*Verify:* the initContainer's log says it saw `engine-llm` serving.
Anything else means it started **without a turn**, and a small KV cache
downstream has that as its cause.

**10 — `engine-cpu`, then the gateway and the mode controller.** The
gateway mounts four ConfigMaps and one Secret; all must exist or the pod
will not start.

**11 — `aegis org apply` to regenerate the two derived ConfigMaps.**
*Verify:* the regenerated files carry their `hash:` header and `git diff`
is empty when the inputs have not changed.

**12 — Tenant wiring, all three parts together.** A key alone is not
enough. The tenant needs: its `secret-ai-gateway-key`, an egress
NetworkPolicy to the gateway, **and** an entry in the task registry.
Missing the registry entry gives a loud 403. Missing the netpol gives a
**silent timeout**. Grant all three or none.

**13 — `ai start`.** Nothing opens automatically, ever, by design. The
automation only closes.

---

## 4. The traps

These are measured, not theoretical. Each one has cost someone time.

**T-1 — `plans.yaml` must keep its `ai:` block even with no AI.** The
generator indexes it unconditionally; stripping the key raises
`KeyError`. Leaving it costs nothing.

**T-2 — The generator writes into `k8s/base/ai-system/`.** Two of its
stages target that directory. In this seed they are guarded and report
*not applicable* when the subsystem is absent — and **fail loudly** if a
contract declares `ai:` while the subsystem is missing, because that is a
promise nobody can keep. If you restore the subsystem, the guard simply
stops firing; you do not need to touch it.

**T-3 — The `gpu` Application is a fragment inside `core.yaml`.** Anyone
reasoning at directory granularity will miss it, and removing a directory
will not remove it.

**T-4 — The vLLM image digest appears in three places** — the `llm`
Deployment, the `charla` Deployment, and the `charla` initContainer.
Bump two of three and the initContainer runs a different build than the
server it is waiting for.

**T-5 — The gateway image digest appears in two places**, gateway and
controller. One image, two binaries, deliberately.

**T-6 — The VRAM preflight threshold and the engines' memory fraction
are one decision split across two files.** Move one without the other and
you get either a preflight that blocks legitimate starts or one that
waves through an out-of-memory.

**T-7 — The namespace GPU quota and the device plugin's replica count are
also one decision in two files.** The quota exists so that a *third* GPU
pod is rejected at admission instead of hanging `Pending` forever. Raise
either alone and you get silent Pending.

**T-8 — The engine Deployments deliberately have no `replicas:` field.**
Writing one back makes every sync of the Application bounce both engines;
the controller re-raises them seconds later. The `ignoreDifferences` rule
is present and does **not** prevent this.

**T-9 — `ignoreDifferences` protects the diff, not the apply.** Measured
twice: a sync reverted the mode ConfigMap in under ten seconds and the
controller scaled the GPU down behind it. The only thing that works is
**git not declaring the field at all**, which is why the mode ConfigMap
ships with no `data:` block. That apparent omission is the mechanism. Do
not "fix" it.

**T-10 — In `ignoreDifferences`, `group` must be *absent*, not empty.**
The API server drops an empty string on read, so git and the live object
disagree forever. This is the opposite of the AppProject blacklist, where
the empty string is correct.

**T-11 — The node's internal IP is hardcoded in one NetworkPolicy** and
appears exactly once in the whole tree, so nothing will flag a mismatch.
On a different node the symptom is the controller logging that it cannot
read the mode, and the GPU staying wherever it was.

**T-12 — Prompt prefixes must be byte-stable.** The engines' prefix cache
takes time-to-first-token from ~1000 ms to ~25 ms. Inserting a date, a
visitor name or a counter invalidates it on **every** request, with no
error — just forty times slower. It is the easiest mistake to make and
the hardest to notice.

**T-13 — The in-flight limit and the engine's sequence limit are supposed
to match**, and for one of the two lanes they currently do not. Not a
crash: requests wait inside the engine instead of in the queue. Someone
"fixing" it changes queue semantics, so know that before you do.

**T-14 — `sops -d <file> | head -c 1 && echo ok` lies.** The `&&` still
short-circuits true when `head` reads the first byte of a *stderr failure
message*. This is documented elsewhere in this repo as the canonical
example of a reading that lies. Do not use it as a verification step.

**T-15 — `SOPS_AGE_KEY_FILE` must be set explicitly.** This instance's
identity is not the file sops defaults to. Omitting it fails with a
misleading "no such file or directory" even though the key exists.

**T-16 — Rotating a tenant key does not revoke the old one.** The tool
prints exactly that warning. Revocation is a separate, manual act.

**T-17 — The CPU engine's `Recreate` strategy cannot be applied to a
Deployment that was born `RollingUpdate`.** Strategic merge will not drop
the `rollingUpdate` block and kustomize prunes the null that would.
Born fresh it is fine; converting a half-restored one is not.

---

## 5. How to know you are done

Not "the pods are green". The subsystem is attached when:

1. the node advertises `nvidia.com/gpu: 2`;
2. `engine-charla`'s initContainer logged that it waited its turn;
3. `ai status` reports the mode, both engines, and VRAM in use;
4. a tenant BFF can reach the internal gateway with its key and get an
   answer — not a 403 (missing registry entry) and not a timeout
   (missing netpol);
5. `aegis org apply` regenerates the two derived ConfigMaps with no diff.

If any of the five is unverified, say so rather than declaring the
subsystem attached. An AI lane that is half-wired fails silently, in
production, at the worst moment — which is the whole reason this file
exists.
