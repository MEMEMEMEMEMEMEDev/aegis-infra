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

There is no AWS, GCP or Azure behind it. It runs on one machine the
operator owns or rents, and the same stack runs on a laptop at home, on
a VPS or on a bare-metal box. For you that is transparent.

---

## The deal: what you put in, what the platform does

**You, in your app's repo:**
- Your code.
- A `Containerfile` (how your image is built). Its `FROM` is one of the
  platform's own base images, pinned by digest; the template already
  carries it and `aegis image from` prints the one to paste.
- A `Jenkinsfile` — **the template hands it to you**, you barely touch
  it.
- Your app's Kubernetes manifests (Deployment, Service, the kustomize
  overlay) — templated as well.

**The operator, in the platform repo:** your organization's **contract**,
one YAML (`orgs/<name>.yaml`) that declares your services, your public
paths, your database, your bucket and your plan. Everything the cluster
holds for you — namespace, quota, network rules, routing, the CI job —
is derived from it. You never edit cluster manifests.

**The platform, on its own, on every push:**
1. **Builds** your image (unprivileged, isolated).
2. **Scans** the image (Trivy), layer by layer. What *your change* brings
   with a fixable critical or high vulnerability makes the build red;
   what your base image carries is the platform's, judged and re-scanned
   by the platform every morning; what was already running is written
   down as debt with a due date. An exploited-in-the-wild CVE has no due
   date: it blocks.
3. **Signs** the image (cosign, by digest).
4. **Publishes** it to the internal registry.
5. **Writes the digest** into your repo's overlay and commits it; ArgoCD
   syncs it onto the cluster.
6. **Exposes** it with TLS at your hostname — you touch no DNS, no
   certificate and no tunnel. Only pushes to `main` deploy; every other
   branch still builds, scans and signs, so it keeps proving your code is
   sound.

---

## The life cycle of a push

```
git push
   │
   ▼
webhook ──▶ Jenkins (build of your branch)
              │
              ├─ image build (unprivileged, from a base the platform signed)
              ├─ vulnerability scan  ── a new fixable CRITICAL/HIGH of yours ⇒ FAILS
              ├─ push to the internal registry
              ├─ signature (cosign, by digest)
              └─ main only: the digest is committed to your overlay
                    │
                    ▼
              ArgoCD detects the commit and syncs
                    │
                    ▼
              Kyverno admits ONLY images signed by the platform
                    │
                    ▼
              your app running, with TLS, at your hostname
```

All of this is automatic. If the build goes red, the stage log in Jenkins
tells you exactly which step (build / scan / push / sign / deploy) and
why, and `aegis builds` (or the console's Deployments screen) shows every
push with its four links measured.

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

2. **Your `FROM` is one of the platform's bases.**
   The build refuses a Containerfile whose base is not a platform image
   pinned by digest. Ask the operator for a base the platform does not
   ship yet (`aegis image request`); it is mirrored, scanned and signed
   before you can use it.

3. **The scan blocks what you bring.**
   A fixable CRITICAL or HIGH that your change introduces breaks the
   build. The fix is to update the dependency, not to skip the scan. What
   your base carries is not your build's verdict; the platform watches
   it every morning and `aegis vulns` says what is owed and until when.

4. **Every container needs `resources.limits`.**
   There is a strict per-namespace quota. A container with no `limits`
   (cpu and memory) **is not created** — not init containers, not sidecars
   either. The template already carries them; if you add a container, add
   limits to it. Sizes come from the contract (`tamano`), not from
   numbers you pick.

5. **The network starts closed (default-deny).**
   By default your app can talk to nothing except DNS and the edge that
   exposes it. If your app needs to reach something (your database, the
   internet, the AI gateway), that is declared in the contract (`usa:`)
   and derived into a network rule — ask the operator, do not assume there
   is a way out.

6. **Every app lives in its organization's namespace.**
   You neither see nor touch other organizations' apps. The isolation is
   by design: its own namespace, quota and network per organization. The
   routing (which hostname and path reach which service) is derived from
   the contract; your repo cannot write its own.

7. **No privileged pods.**
   Your app runs as an ordinary process, with no node privileges and a
   read-only root filesystem. If your image needs root for something
   unusual, let us talk it over first — there is almost always another
   way.

8. **Secrets never in cleartext in Git.**
   Passwords, tokens, keys: never committed as plain text. A credential
   the platform cannot invent (a cloud key, a chosen password) is declared
   in the contract (`secretos:`) and stored with `aegis secret put`; it
   reaches your pod as a Kubernetes Secret. No committed `.env`.

---

## What you do NOT have to do (the platform swallows it)

- You do not administer the image registry.
- You do not issue or renew TLS certificates.
- You do not configure DNS or the tunnel to the internet.
- You do not sign images by hand.
- You do not write cluster manifests, network rules or routing.
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
| **The edge**          | Cloudflare's tunnel, or the host itself: what puts it on the internet (automatic). |
| **The console**       | The operator's screens: your project, its deployments, its traffic, its storage. |

There are also **local language models** available as a service if your
app needs them, through the platform's AI gateway — without depending on
an external provider. Your app consumes them as one more URL with a key
the operator issues per project (`usa: [ai]` in the contract); where the
inference runs is transparent to you.

---

## How to get started

1. Ask the operator for your organization (its contract, with your repo
   and your services) and pick a template: `base`, `static`,
   `service-node`, `service-python`, `service-java` or `worker-go`.
2. Start from what the template seeded: `Containerfile` + `Jenkinsfile`
   + the app's manifests. The canonical Jenkinsfile lives in
   `platform/docs/protocols/templates/Jenkinsfile.app`.
3. `git push`.
4. Watch the build in Jenkins, or ask the operator to show you the
   Deployments screen.
5. Your app shows up at your hostname, over HTTPS, signed and scanned.

The first deploy is the best way to understand the whole cycle. If
something fails, the stage log in Jenkins is the first place to look; the
cause is there.
