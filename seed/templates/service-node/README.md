# Template `service-node` — a JavaScript server behind the edge

Tested and installed with the platform's CI node image, run on the node
base aegis owns. It stands up in one run and, from that second on, the
template is gone from your life: what it wrote is yours (§0.3).

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
- **The digest marker in `k8s/overlays/dev/`** — the pipeline writes
  the real one on every build.
- **The public route** — derived by the platform from the contract;
  this repo is not allowed to declare one.
