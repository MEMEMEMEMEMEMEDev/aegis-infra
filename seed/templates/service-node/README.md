# Template `service-node` — a JavaScript server behind the edge

Installed and tested by the pipeline, run on a node runtime that
carries neither npm nor a shell. From the second it is instantiated the
template is gone from your life: what it wrote is yours (§0.3).

## How it is built (since 2026-10-02)

The pipeline's `compile` stage runs `ci/compile.sh` in `aegis-ci-node`,
a container the platform builds and scans itself: `npm ci`, `npm test`,
`npm prune --omit=dev`. The Containerfile only copies the manifest, the
production `node_modules` and `src/` onto the runtime,
`nodejs-distroless:22`, which is mirrored, scanned and signed. Nothing has
to be mirrored before the template instantiates.

It used to install and test INSIDE the image build, on
`node:22.23.1-alpine`. That image had to be mirrored first, and on
the Arch lab VM the door retained it: its bundled npm carried eleven CVEs past
their window. The static template made the same move on 2026-09-30.

## What you change

- **`src/server.js`** — your app. It starts as node's stdlib and
  nothing else, which is a deliberate zero: an empty dependency tree
  cannot rot and has nothing for the scan to argue about.
- **`tests/`** — the suite `npm test` runs in the pipeline's `compile`
  stage, before the image is built. It is the image's door: a red test
  stops the pipeline there and the image never comes to exist.
- **`package.json` + the lock** — add dependencies normally. Commit the
  lock: the build installs with `npm ci`, which refuses to guess.
- **The contract** — `usa: [postgres]`, `usa: [bucket]`, `usa: [ai]`.
  This is the type that may hold a credential; a static front may not.

## What you do not change, and why

- **Port 8080 and `USER 65532:65532`** — the tenant NetworkPolicy
  admits edge -> 8080 only, and PSS restricted rejects a non-numeric
  user. Listen on 0.0.0.0, not on localhost: the probe comes from
  outside the process.
- **The `FROM` line** — resolved against the internal registry at
  instantiation and pinned by digest. The runtime carries no npm and no
  shell; the npm that installs is the pipeline's.
- **`ci/compile.sh`** — `npm ci`, `npm test`, `npm prune --omit=dev`,
  `mkdir -p node_modules`. The `mkdir` is load bearing while your
  dependency tree is empty: `npm ci` creates no `node_modules` at all in
  that case (measured: «up to date in 134ms», and no directory), and the
  Containerfile's `COPY` of a path that does not exist aborts the build
  with an error that never mentions npm.
- **`.dockerignore`** — an allowlist (the manifest, `node_modules`,
  `src/`): the tests and anything you add tomorrow stay out of the image.
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
come from the internal registry's own listing) hands that line's
maintenance to the base-images job: it rewrites the digest on every
rebuild of the base.
The contract that image keeps is the same one this file assumes — uid
65532, `/app` as WORKDIR, port 8080, node as the ENTRYPOINT — so the
`FROM` is the only line that changes. It is also the move to make before
a dependency with a native addon (bcrypt, sharp…): those are compiled in
`aegis-ci-node`, which is Alpine (musl), and they run on
`aegis-base-node` (Alpine) but not on `nodejs-distroless` (glibc).
