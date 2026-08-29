# Template `service-python` — a python server behind the edge

Built and run on the same mirrored python image. It stands up in one run
and, from that second on, the template is gone from your life: what it
wrote is yours (§0.3).

## What you change

- **`src/server.py`** — your app. It starts as the stdlib and nothing
  else, which is a deliberate zero: an empty dependency tree cannot rot
  and has nothing for the scan to argue about.
- **`tests/`** — the suite the build runs. It is the image's only gate:
  the canonical Jenkinsfile does not run tests, so a red test here is
  the one thing that stops a bad image from existing.
- **`requirements.txt` and the commented `pip install`** — both, and in
  that order. The install line is commented because a tenant build runs
  inside the cluster, where reaching an index is a decision somebody has
  to make. Pin with hashes when you uncomment it.
- **The Containerfile's single stage** — split it in two the day you
  install wheels with C behind them: build here, copy the site-packages
  into a fresh image. Never leave a compiler in the runtime.

## What you do not change, and why

- **Port 8080 and `USER 65532:65532`** — the tenant NetworkPolicy
  admits edge -> 8080 only, and PSS restricted rejects a non-numeric
  user. Listen on 0.0.0.0: the probe comes from outside the process.
- **`PYTHONDONTWRITEBYTECODE`** — the root filesystem is read only, so
  the bytecode cache python tries to write beside every module fails
  silently and every start re-parses the sources.
- **The `FROM`** — resolved against the internal registry at
  instantiation and pinned by digest.
- **The digest marker and the public route** — the pipeline writes the
  first; the platform derives the second from the contract.
