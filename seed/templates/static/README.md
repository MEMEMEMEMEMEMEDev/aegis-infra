# Template `static` — a front for Astro, React, Vue or Angular

Built with a node image that carries npm, served by node's standard
library on the runtime the platform mirrors, scans and signs. From the
second it is instantiated the template is gone from your life: what it
wrote is yours (journeys/design.md §0.3).

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
and the same libc.

Images are mirrored when somebody needs one, not in advance
(`docs/protocols/images.md` §2). Being told which one, before anything
is written, is the mechanism working.

## What you change

- **`Containerfile`, the two ARGs at the top** — `BUILD_CMD` and
  `OUT_DIR`. They are the only thing that differs between the four
  frameworks; the table with the four values is right above them.
- **`package.json` + the source tree** — run `npm create astro@latest`
  (or vite, or the Angular CLI) here and let it overwrite them. Keep the
  lock file: the build installs with `npm ci`, which refuses to guess.
- **`serve.mjs`, the `SPA_FALLBACK` constant at the top** — true for a
  single-page app (React, Vue, Angular), false for a multi-page build
  (Astro and friends). Get it wrong the second way and a typo answers
  200 with the home page, lying to the visitor and to your uptime probe.

## What you do not change, and why

- **Port 8080 and `USER 65532:65532`** — the tenant NetworkPolicy
  admits edge -> 8080 only, and PSS restricted rejects a non-numeric
  user. The server binds 0.0.0.0: the probe comes from outside the
  process.
- **The two `FROM` lines** — they are resolved against the internal
  registry when the template is instantiated, pinned by digest. A base
  pulled off the internet is unmirrored, unscanned and unsigned.
- **`k8s/overlays/dev/kustomization.yaml`'s digest marker** — the
  pipeline writes the real one there on every build.
- **The public route** — it is derived by the platform from
  `orgs/<org>.yaml`; this repo is not allowed to declare one.

## The one change worth making later: nginx

The platform's own static fronts run on `aegis-base-nginx`, a base aegis
builds and patches. A template cannot start there, and the reason is
mechanical rather than a preference: that image is tagged
`<alpine minor>-<build number>`, the number is born in your instance's
registry, and what resolves a template's FROM needs an exact tag — so
the seed has no tag to name. `serve.mjs` says the same at length.

Once this repo has built once you are past that. From `aegis org apply`
onwards the repo is listed in `base-images/consumers.txt`, so swapping
the runtime `FROM` for `aegis-base-nginx:<tag>@sha256:<digest>` (both
come from the internal registry's own listing) hands that line's
maintenance to the base-images job: it rewrites the digest on every
rebuild of the base, which is why the platform's fronts moved onto it.
Then delete
`serve.mjs`, copy your build into `/usr/share/nginx/html/` and put a
`server{}` with `listen 8080` at `/etc/nginx/conf.d/default.conf`.

To add a database, a bucket or AI, edit the contract and reapply. A
static front can hold no credential: put those behind an `http` service.
