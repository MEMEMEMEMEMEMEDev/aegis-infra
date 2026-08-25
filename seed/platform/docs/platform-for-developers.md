# The platform, for the development team

Context on the infrastructure your applications run on. It does not cover
everything — it covers what you need to know in order to deploy without
crashing into anything. If something here blocks you and you do not know
why, the answer is almost always in the "Rules that will reject you"
section.

---

## In one sentence

It is a self-hosted Kubernetes platform with GitOps. You write code; the
platform builds it, scans it, signs it, deploys it and exposes it to the
internet — without you touching infrastructure. Your job ends at
`git push`.

There is no AWS/GCP/Azure behind it. It runs on our own hardware and is
designed to be portable (the same stack runs on a VPS if we ever migrate).
For you that is transparent.

---

## The deal: what you put in, what the platform does

**You, in your app's repo:**
- Your code.
- A `Containerfile` (how your image is built).
- A `Jenkinsfile` — **we hand it to you as a template**, you barely touch
  it.
- Your app's K8s manifests (Deployment, Service, etc.) — templated as
  well.

**The platform, on its own, on every push:**
1. **Builds** your image (unprivileged — an isolated, safe build).
2. **Scans** the image (Trivy). A serious vulnerability with a fix
   available = a red build. Code with known CVEs does not get deployed.
3. **Signs** the image (cosign, by digest).
4. **Publishes** it to the internal registry.
5. **Deploys** it through GitOps (ArgoCD syncs the repo's state onto the
   cluster).
6. **Exposes** it with TLS and publishes it to the internet — you touch
   no DNS, no certificates and no tunnel.

---

## The life cycle of a push

```
git push
   │
   ▼
webhook ──▶ Jenkins (build of your branch)
              │
              ├─ image build (unprivileged)
              ├─ vulnerability scan  ── CRITICAL/HIGH with a fix ⇒ FAILS
              ├─ push to the internal registry
              └─ signature (cosign)
                    │
                    ▼
              ArgoCD detects the change and syncs
                    │
                    ▼
              Kyverno admits ONLY images signed by the platform
                    │
                    ▼
              your app running, with TLS, at your-app.<dominio>
```

All of this is automatic. If the build goes red, the stage log in Jenkins
tells you exactly which step (build / scan / push / signature) and why.

---

## Rules that will reject you (read this)

These are the platform's guard rails. They are not negotiable from your
app — they belong to the cluster. Knowing them saves you hours of "why
does my pod not start".

1. **Only images signed by the platform run.**
   You cannot bring up `nginx:latest` from Docker Hub, nor an image you
   put together on your own machine. If it did not go through the pipeline
   (build + scan + signature), the cluster **rejects it at admission**,
   citing the signature policy. Everything that runs, runs because the
   platform built it and signed it.

2. **The scan blocks.**
   A CRITICAL or HIGH CVE with a patch available breaks the build. The fix
   is to update the dependency, not to skip the scan. The scan is the part
   that ages on its own and tells you when your base image has gone stale.

3. **Every container needs `resources.limits`.**
   There is a strict per-namespace quota. A container with no `limits`
   (cpu and memory) **is not created** — not init containers, not sidecars
   either. The template already carries them; if you add a container, add
   limits to it.

4. **The network starts closed (default-deny).**
   By default your app can talk to nothing except what is explicitly
   allowed (DNS and the edge that exposes it). If your app needs to reach
   another service (a DB, an external API), that is enabled with an
   explicit network rule — ask for it, do not assume there is a way out.

5. **Every app lives in its organization's namespace.**
   You neither see nor touch other organizations' apps. The isolation is
   by design: its own namespace, quota and network per organization.

6. **No privileged pods.**
   Your app runs as an ordinary process, with no node privileges. If your
   image needs root for something unusual, let us talk it over first —
   there is almost always another way.

7. **Secrets never in cleartext in Git.**
   Passwords, tokens, keys: never committed as plain text. There is an
   encrypted mechanism (SOPS+age) for that. If you need a secret for your
   app, it is managed through there, not in a committed `.env`.

---

## What you do NOT have to do (the platform swallows it)

- You do not administer the image registry.
- You do not issue or renew TLS certificates.
- You do not configure DNS or the outbound tunnel to the internet.
- You do not sign images by hand.
- You do not touch the Kubernetes infrastructure or the IaC.
- You do not contract or pay for cloud services.

If you find yourself doing any of these, something has come off the rails
— say so.

---

## The stack you actually see

| Piece                 | What it is for you                                 |
|-----------------------|----------------------------------------------------|
| **GitHub**            | Where your code lives; everything starts here.     |
| **Jenkins**           | Where you see your branch's build (logs, status).  |
| **Internal registry** | Where your image ends up (you do not touch it).    |
| **ArgoCD**            | What syncs your repo → cluster (GitOps).           |
| **Ingress + TLS**     | What exposes your app over HTTPS (automatic).      |
| **Cloudflare**        | The edge that puts it on the internet (automatic). |

There are also **local language models** (Ollama and the like) available
as a service if your app needs them — without depending on OpenAI or any
external provider. Your app consumes them as one more URL (configured per
environment); where the inference runs is transparent to you.

---

## How to get started

1. Ask for your repo and your organization (namespace) on the platform.
2. Start from the template: `Containerfile` + `Jenkinsfile` (the canonical
   one lives in `platform/docs/protocols/templates/Jenkinsfile.app`) + the
   app's manifests.
3. `git push`.
4. Watch the build in Jenkins.
5. Your app shows up at `your-app.<dominio>`, over HTTPS, signed and
   scanned.

The first deploy is the best way to understand the whole cycle. If
something fails, the stage log in Jenkins is the first place to look; the
cause is there.
