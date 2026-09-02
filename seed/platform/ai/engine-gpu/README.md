# engine-gpu — the vLLM image, reproducible at last

**Status: VERIFIED 2026-09-02.** Built, scanned clean, signed,
deployed, started and answering a request that arrived from the public
internet. It was written on a machine with no GPU and no cluster, from
the upstream build definitions rather than from an execution — and the
first execution is what turned four defensible pins into measured ones.

| | |
|---|---|
| build | 24 min, image scanned with 0 findings |
| weights loaded | 3.29 GiB in 2.27 s |
| KV cache | 18,192 tokens · concurrency 1.48x at 12,288 per request |
| both lanes | llm + mt on one RTX 5070, 10,173 of 12,227 MiB in use |
| end to end | 200 in 0.53 s through the public site |

**What the first build corrected**, each in place with its measurement:

- **cu128 → cu130.** The reasoning for naming the index was right; the
  half that was missing was which CUDA vLLM itself was compiled
  against. Its own metadata says `nvidia-cutlass-dsl[cu13]`.
- **libc6-dev.** `gcc-14` was installed and `CC` pointed at it, and
  `--no-install-recommends` had dropped the C headers. A compiler with
  no `stdlib.h` is not a compiler.
- **A passwd entry for uid 1000.** The manifests already set `HOME`
  because the user had none; that answered «where do I live». torch
  asks «what is my name».
- **0.38 → 0.42 of the card.** Fifty megabytes short of the KV cache a
  single request at full context needs.

None of those was visible without running it, and that is the whole
argument for the banner that used to be here.

## What it replaces

The GPU engines used to run an image assembled BY HAND, in a ceremony
that was dismantled afterwards and recorded as not reproducible from
the internet: a frozen virtualenv packaged as OCI layers. It had gone
through the same rite as any third party — blocking scan before the
push, signature by digest, the key never leaving the cluster — but it
had no build. If the internal registry were lost and that virtualenv
were lost with it, both GPU lanes would have been unrecoverable.

That was the last thing in the platform that could not be rebuilt from
source.

## The pins, and why they are the file's whole content

The target is a Blackwell **consumer** card, compute capability
`sm_120`. It is not the same architecture as the datacenter Blackwell
(`sm_100`), so "this release supports Blackwell" is not an answer to
the question this image asks. Each pin was measured against the
upstream build definition, and each measurement is cited beside the pin
in the Containerfile with its URL and its date.

The load-bearing one is not the torch version — it is the CUDA variant.
PyTorch's wheel build compiles `12.0` (that is `sm_120`) **only** for
the CUDA 12.8 wheels; the cu126 wheel of the very same torch version
carries no kernels for this card and fails at the first matmul. That is
why the index is named explicitly and why the local version `+cu128` is
written into the pin.

## What it deliberately does not carry

`nvcc`. Any path that compiles CUDA at runtime dies in this image, and
the one that matters is FP8: the engines serve bf16 activations with
int4 or bf16 weights, never FP8. The Containerfile explains where the
edge is and what adopting FP8 would cost, so that whoever wants it
starts from the measurement instead of from a version bump.

## The first build IS the verification

Fire the job, and while it runs watch for these, in this order:

1. **the FROM resolved.** The preflight stage fails if it is still a
   placeholder. `aegis ai images` is what resolves it, against the live
   internal registry.
2. **the scan.** This image has an operating system and native wheels,
   so the scan looks at everything: distribution packages and Python
   dependencies alike. A red scan has two honest ways out — a newer pin
   or a dated, reasoned exception — and no third one.
3. **the engine actually starting.** The build passing proves the image
   exists, not that it runs. The proof is `aegis ai start` followed by
   the engine reaching Ready, and the number to read in its log is the
   KV cache: a NEGATIVE value means two engines measured free VRAM at
   the same instant, which is what the second lane's init container
   exists to prevent.

That is what was done on 2026-09-02: the banner in the Containerfile
was replaced by the numbers, not deleted. A banner removed without
those numbers is just a banner removed — and the numbers are the only
part of it that a reader can check.

## What is still owed

The job that would run this pipeline does not exist: registering it is
one item in `jenkins/values.yaml`'s job-dsl, alongside `ci-images`,
`mirror-images`, `base-images` and `image-watch`. Until that item is
there, this Jenkinsfile is a build definition nobody can fire, which is
exactly the shape check 137 was written to catch one level up.
