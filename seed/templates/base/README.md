# Template `base` — a bare HTTP service

The smallest one that compiles and deploys (journeys/design.md §4). It
exists so that `aegis app new <org> --template base` leaves you, in one
run and without touching the world, everything the artisan path writes
by hand.

## What it stands up

| piece | where it comes from |
|---|---|
| `orgs/<org>.yaml` | `contract.yaml.tpl`, with `__ORG__`/`__DOMINIO__`/`__REPO__` resolved |
| `.aegis-app/<org>/app/` | `repos/app/` — the skeleton of the app's repo |
| manifests of `k8s/organizations/org-<org>/` + jobs + edge | NOT from this template: `aegis org` derives them FROM THE CONTRACT |
| `.enc.yaml` secrets | not those either: `aegis secret create` creates them |

The skeleton is Go with **zero external dependencies** on purpose
(journeys §5, rot budget): an empty dependency tree cannot rot. It
brings `main.go` + `go.mod`, a non-root `Containerfile` (PSS
restricted), `k8s/base/` + `k8s/overlays/dev/` with the digest marker
the pipeline rewrites, and `ci/write-digest.mjs` (copied from the
canonical one in `docs/protocols/templates/`). The `Jenkinsfile` does
**not** live here: `aegis org` instantiates it from the canonical
template into the same staging area (journeys §2b) — one single
template, zero copied CHANGEMEs.

## What evaporates once instantiated

The template generates the contract and the initial code and
**disappears from your life** (journeys §0.3): nothing it generated
remembers where it came from, nor ever reads it again. There is no
"template upgrade", you are not "a base app": you are an artisan with a
contract and a repo, just like whoever wrote them by hand. Editing this
folder changes no organization already created.

## How it is customized afterwards (the artisan path)

By editing **the contract**, which is the only truth, and reapplying:

    $EDITOR orgs/<org>.yaml          # add postgres, bucket, ai, another service…
    aegis org apply orgs/<org>.yaml
    aegis secret create orgs/<org>.yaml   # if new secrets appeared

(`aegis app new <org>` without `--template` runs exactly those two
steps for you.) The app's code is customized in ITS repo, like any
other repo: the living reference for a fuller path —two images,
database, bucket, AI— is `ejemplo-app` (orgs/ejemplo.yaml).

## The two `FROM` lines

They are placeholders (`__FROM_GOLANG__`, `__FROM_ALPINE__`) that
`aegis app new` resolves against the INTERNAL registry when it
instantiates, writing the reference pinned by digest. Until 2026-08-29
they read `docker.io/library/...`: an image pulled off the internet, by
a mutable tag, in the very pipeline that afterwards signs the result —
the hole the image mirror exists to close, taught to every new
organization by the template. The digest cannot be computed offline:
the mirror rebuilds the manifest as it copies, so upstream's digest is
not the one that pulls here.

## The other templates

`static` (Astro, React, Vue, Angular), `service-node`,
`service-python`, `service-java` and `worker-go` — the same structure,
each with its own README saying what to change and what not.
