# Template `service-node` — a JavaScript server behind the edge

Tested and installed with a node image that carries npm, run on a node
runtime that carries neither npm nor a shell. From the second it is
instantiated the template is gone from your life: what it wrote is
yours (§0.3).

## Before it will instantiate: one image has to be mirrored

The build image, `node:22.23.1-alpine`, is not in
`mirror-images/images.txt`. `aegis app new` therefore STOPS before
writing a single file and prints the exact command that mirrors it —
read that line off the screen rather than from here, so there is one
place it can be wrong. The runtime image, `nodejs-distroless:22`, is
already declared and needs nothing.

That build version is not a choice made here: it is the one
`ci-images/node/Containerfile` already pins, so what a tenant builds in
and what the platform's own CI is built from stay the same 22.23 line
and the same libc — which is what makes the `node_modules` this build
produces the ones the runtime expects.

Images are mirrored when somebody needs one, not in advance
(`docs/protocols/images.md` §2). Being told which one, before anything
is written, is the mechanism working.

## What you change

- **`src/server.js`** — your app. It starts as node's stdlib and
  nothing else, which is a deliberate zero: an empty dependency tree
  cannot rot and has nothing for the scan to argue about.
- **`tests/`** — the suite `npm test` runs INSIDE the build. It is the
  image's only gate: the canonical Jenkinsfile does not run tests, so a
  red test here is the one thing that stops a bad image from existing.
- **`package.json` + the lock** — add dependencies normally. Commit the
  lock: the build installs with `npm ci`, which refuses to guess.
- **The contract** — `usa: [postgres]`, `usa: [bucket]`, `usa: [ai]`.
  This is the type that may hold a credential; a static front may not.

## What you do not change, and why

- **Port 8080 and `USER 65532:65532`** — the tenant NetworkPolicy
  admits edge -> 8080 only, and PSS restricted rejects a non-numeric
  user. Listen on 0.0.0.0, not on localhost: the probe comes from
  outside the process.
- **The two `FROM` lines** — resolved against the internal registry at
  instantiation and pinned by digest. The build image carries npm, the
  runtime one does not, and that asymmetry is the point.
- **`RUN npm ci ... && mkdir -p node_modules`** — the `mkdir` is load
  bearing while your dependency tree is empty: `npm ci` creates no
  `node_modules` at all in that case (measured: «up to date in 134ms»,
  and no directory), and the runtime stage's `COPY` of a path that does
  not exist aborts the build with an error that never mentions npm.
- **The digest marker in `k8s/overlays/dev/`** — the pipeline writes
  the real one on every build.
- **The public route** — derived by the platform from the contract;
  this repo is not allowed to declare one.

## The one change worth making later: aegis-base-node

On 2026-08-27 the platform's own backends moved off `nodejs-distroless`
and onto `aegis-base-node`, a base aegis builds and patches — because
an OpenSSL CVE reached the distroless image and its upstream had not
rebuilt, so there was no place of ours to run the fix. A template cannot
start there, and the reason is mechanical rather than a preference: that
image is tagged `<alpine minor>-<build number>`, the number is born in
your instance's registry, and what resolves a template's FROM needs an
exact tag — so the seed has no tag to name.

Once this repo has built once you are past that. From `aegis org apply`
onwards the repo is listed in `base-images/consumers.txt`, so swapping
the runtime `FROM` for `aegis-base-node:<tag>@sha256:<digest>` (both
come from the internal registry's own listing) hands the maintenance of that line to the
base-images job: it rewrites the digest on every rebuild of the base.
The contract that image keeps is the same one this file assumes — uid
65532, `/app` as WORKDIR, port 8080, node as the ENTRYPOINT — so the
`FROM` is the only line that changes.
