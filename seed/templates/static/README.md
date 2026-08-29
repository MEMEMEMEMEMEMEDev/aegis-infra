# Template `static` — a front for Astro, React, Vue or Angular

Built with the platform's CI node image, served by the nginx base aegis
owns. It stands up in one run and, from that second on, the template is
gone from your life: what it wrote is yours (journeys/design.md §0.3).

## What you change

- **`Containerfile`, the two ARGs at the top** — `BUILD_CMD` and
  `OUT_DIR`. They are the only thing that differs between the four
  frameworks; the table with the four values is right above them.
- **`package.json` + the source tree** — run `npm create astro@latest`
  (or vite, or the Angular CLI) here and let it overwrite them. Keep the
  lock file: the build installs with `npm ci`, which refuses to guess.
- **`nginx.conf`** — the SPA fallback is on. For a multi-page build
  (Astro and friends) swap `/index.html` for `=404`, or a typo answers
  200 with the home page and lies to your uptime probe.

## What you do not change, and why

- **`listen 8080` and `USER 101`** — the tenant NetworkPolicy admits
  edge -> 8080 only, and PSS restricted rejects a non-numeric user. Move
  either and the pod starts fine and never serves anybody.
- **The two `FROM` lines** — they are resolved against the internal
  registry when the template is instantiated, pinned by digest. A base
  pulled off the internet is unmirrored, unscanned and unsigned.
- **`k8s/overlays/dev/kustomization.yaml`'s digest marker** — the
  pipeline writes the real one there on every build.
- **The public route** — it is derived by the platform from
  `orgs/<org>.yaml`; this repo is not allowed to declare one.

To add a database, a bucket or AI, edit the contract and reapply. A
static front can hold no credential: put those behind an `http` service.
