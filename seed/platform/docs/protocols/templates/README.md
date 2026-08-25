# Templates for an app's repo

What lives here is the starting point of an app that consumes the
platform. Three files, and they travel together:

| file | goes into the app's repo as |
|---|---|
| `Jenkinsfile.app` | `Jenkinsfile` |
| `write-digest.mjs` | `ci/write-digest.mjs` |
| `kustomization.overlay.yaml` | `k8s/overlays/dev/kustomization.yaml` |

Change **only** what is marked `CHANGEME`. The rest is a contract with
the platform —pins, secrets, limits—; if any of that does not suit you,
the change goes in the platform's repo, not in your app.

## There are TWO references, and copying the wrong one hurts

**This template** is for the **first app of a freshly born instance**.
It tolerates infrastructure that does not exist yet: during phases
50-70 of the init there is no trivy-server and no cosign key, so `scan`
and `sign` are **skipped with a WARN** instead of breaking the build.

**`ejemplo-app`** is the **living reference**: a real app on an
instance that already works. It tolerates nothing — if trivy-server
does not answer, the build falls over. And it runs on every push, so it
does not rot.

Which one to copy:

- A new instance, still starting up → **this template**.
- A new app on an instance that already runs → **`ejemplo-app`**, which
  also shows the full path with a database, a bucket and two images in
  the same repo.

**Do not mix them.** Bringing the bootstrap tolerance into a real app
is hand-installing a pipeline that cannot tell *"scanned and clean"*
from *"never scanned"*. That is exactly the kind of blind signal this
platform exists to eliminate. Once the instance is standing, a trivy
that is down **has** to break the build.

## What the template CANNOT give you

The bootstrap tolerance is the only thing this template has and
`ejemplo-app` does not. Everything else —the `desplegar` stage, the
deploy by digest, `safe.directory`, the branch guard— is in both, and
whatever is better explained in `ejemplo-app` is the source.

## What has to exist first

In the `jenkins-system` namespace (the init creates them, see
`registry-credentials.md`):

- `Secret regcred-internal` — the registry's dockerconfigjson
- `Secret aegis-ca-trust` — the internal CA's `ca.crt`
- `Secret cosign-signing-key` — `cosign.key` + `cosign.password`

And a `github-token` credential in Jenkins with **write** permission on
the app's repo: the `desplegar` stage commits the digest.

Routing does **not** have to be declared. Since #54 the platform
derives it from the organization's contract (`orgs/<org>.yaml`), and
the app's repo cannot write it even if it wanted to. What you do have
to respect is the naming convention: service `X` of the contract is
exposed as Service `<org>-X` on port **8080**.

## History, because it explains the shape

Until 2026-08-06 this template **had no deploy stage**. Whoever copied
it got a pipeline that built, scanned, published and signed the image —
and then deployed nothing. It ended green, because it did everything it
said it did: what was missing was not broken, it was **absent**, and no
check looks at what does not exist.

The canary copied it as it was and stayed that way for months without
anyone noticing.

The lesson stayed baked into the `Jenkinsfile.app` comments, and it is
worth more than the file: **a template nobody exercises rots**. That is
why the reference for the normal case is `ejemplo-app`, which really
runs on every push, and this template is confined to the single case
`ejemplo-app` cannot cover.
