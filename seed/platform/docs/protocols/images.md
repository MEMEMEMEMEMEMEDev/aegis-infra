# Protocol: images — mirrors, owned bases and the daily watch

Status: **contract v1**. This document defines what an operator touches
when a container image enters the platform, when one of them turns out
to be vulnerable, and what the platform does about it on its own every
morning. What changes over time are the LISTS (`images.txt`,
`base-images/`, `consumers.txt`) and the exceptions
(`trivyignore.yaml`), not this contract.

Audience: the operator of an aegis instance. You do not have to be the
author of aegis to read it. If an alert named below wakes you, [§4](#4-what-image-watch-asks-each-morning)
says what it means and what to do; if you are about to add an image,
[§2](#2-adding-or-updating-a-mirrored-image) and [§3](#3-owning-a-base)
are the whole procedure.

---

## 0. Why it exists

On 2026-08-26 OpenSSL published CVE-2026-14456, a QUIC denial of
service in libcrypto3 (3.5.7-r0, fixed in 3.5.8-r0). Build 66 of the
static fronts blocked at the scan, and so did every deploy after it:
the scan is blocking, and it was right to be. Upstream nginx had not
rebuilt its image — `1.31.3-alpine` and `1.31.4-alpine` both carried
the vulnerable library. **A new digest is not a new image**: the tag
moved, the fix was not in it. Alpine 3.22 had shipped openssl 3.5.8-r0
on 2026-08-25, one `apk upgrade` away, and there was no place in the
platform to run that line.

Two things were true at once and neither one cancels the other. The
real exposure was nil: the fronts speak plain HTTP on 8080 behind the
edge, no TLS, no QUIC. And the scanner was still right to block: a
gate that reasons about reachability is a gate somebody will argue
with, and the day it is wrong nobody will notice.

The hole underneath was older than the CVE. Nobody re-looked at what
was already mirrored. The only detector was the blocking scan, and it
only acts on a REBUILD: an image nobody pushes to is never re-scanned,
and the platform had no way to say "the fix exists upstream, go get
it". This protocol closes both: a base aegis OWNS, rebuilt from the
distribution's packages the morning a fix appears, and a WATCH that
asks every morning whether what we serve is still clean.

---

## 1. The three jobs and the watch

```
   THIRD PARTIES                 BASES aegis OWNS              TOOLING
   mirror-images                 base-images                   ci-images
   ─────────────                 ───────────                   ─────────
   images.txt                    base-images/<member>/         ci-images/
   (source@digest → dst:tag)     Containerfile                 Containerfile
        │                              │                            │
   crane pull                     kaniko build                  kaniko build
        │                              │                            │
   trivy (BLOCKING,               contract assertion            push
   trivyignore.yaml               UID 101 · port 8080           (no scan, no sign:
   scoped exceptions)             nginx -t                       nothing runs in
        │                              │                            a tenant)
   crane push                     trivy (BLOCKING,
        │                         NO exceptions)
   cosign sign by digest               │
        │                         push · sign
        ▼                              │
   internal registry ◄─────────────────┤
                                       ▼
                                  commit the new digest into the FROM
                                  of every repo in consumers.txt
                                  → each consumer's own pipeline
                                    rebuilds on the patched base

   ┌───────────────────────────────────────────────────────────────┐
   │ image-watch  (cron H 6 * * *, declared in the job-dsl)        │
   │ re-scans every mirror and every base against TODAY's DB;      │
   │ asks whether each upstream tag moved and whether the          │
   │ candidate is clean; checks trivyignore expiries.              │
   │ NEVER blocks. Pushes metrics + events.                        │
   │ base with a fixable CVE  → fires base-images with those       │
   │                            members                            │
   │ third party with one     → an alert; a human decides          │
   └───────────────────────────────────────────────────────────────┘
```

Three jobs, three kinds of image, three levels of trust:

| job | what | scan | sign | who fires it |
|---|---|---|---|---|
| `mirror-images` | third parties the tenants run (postgres, redis, garage, runtimes) | blocking, with the scoped exceptions of `trivyignore.yaml` | yes, by digest | phase 80 once; a human when `images.txt` changes |
| `base-images` | bases aegis owns (`aegis-base-<member>`) | blocking, **no exceptions** | yes | phase 80 once; image-watch on a fixable CVE; a human |
| `ci-images` | tooling the pipelines run in (`aegis-ci-*`) | none | no | phase 50 (bootstrap); a human |

`ci-images` has no scan and no signature because nothing it produces
ever runs in a tenant namespace: Kyverno's `require-aegis-signature`
does not look at `jenkins-system`. The other two feed the enforce
zone, so both scan, both sign, and the difference between them is
where an exception may live: on a third party's binary we cannot
rebuild, with a measurement and an expiry (`trivyignore.yaml`); on a
base we own, nowhere — we rebuild instead.

Phase 80 fires `mirror-images` once and phase 85 fires `image-watch`
once. That is why alert `ImageWatchSilent` means **stopped**, never
"not yet": the first heartbeat exists from birth.

---

## 2. Adding or updating a mirrored image

One line in `mirror-images/images.txt`, two fields:

```
<source>:<tag>@sha256:<64 hex>    <destination>:<tag>
```

The source is pinned BY DIGEST: a tag is a pointer whoever controls the
source registry can repoint. The tag travels IN the reference
(`name:tag@digest` is a digest reference for every registry client)
so that the watch can ask, every morning, whether that tag moved
upstream — and whether what it moved to is any cleaner. Before
2026-08-27 the tag lived in a comment and no machine could ask.

Above the line, a comment that says WHY this image and not the
obvious alternative, and what its known limits are. The file's
existing entries are the model; a line without its reason is the
first thing a stranger cannot maintain.

To update one:

1. `crane digest <source>:<new-tag>` — the content the new tag points
   at today.
2. Edit the line: tag AND digest in the source, tag in the destination.
3. Commit, push, run the `mirror-images` job (`aegis ci build`, or the
   Jenkins console). It pulls, scans against today's DB, pushes and
   signs. A red run here is the gate working: read the scan, and
   either pick another tag or — for a binary that cannot be rebuilt —
   write an exception with its measurement and its `expired_at`
   ([§5](#5-what-the-loop-does-alone-and-what-it-never-does) says when
   that is allowed).
4. Bump the consumer. For a platform type that is `services.yaml`
   (its digest is the INTERNAL registry's, not the source's — a
   `crane copy` of a multi-arch index does not preserve it; read it
   back with `aegis ci digests`) followed by `aegis org apply`. For an
   app it is the `FROM` in its repo.

Step 4 is separate on purpose. **Mirroring does not deploy.** Pulling
a new image and putting it in production are two decisions, taken by
the same person but not at the same moment, and the watch only ever
tells you when step 1 would be worth doing.

---

## 3. Owning a base

A base is an image aegis BUILDS from the distribution's packages
instead of mirroring somebody's build of them. It is the answer to
§0: when the distro ships the patched package, one `apk upgrade`
picks it up, on our cadence, not a third party's.

### 3.1 A member

```
base-images/
  consumers.txt          ← the repos standing on a base (derived block, §3.4)
  nginx/                 ← one directory per member
    Containerfile        ← FROM <REGISTRY>/alpine:3.22 + apk upgrade + apk add nginx
    nginx.conf
    default.conf
    index.html
```

To add a member: a directory under `base-images/`, a `Containerfile`
in it that honours the contract below, and a comment at its top that
says what consumers it exists for. Nothing to register: `base-images`
builds every directory it finds (or the `MEMBERS` it is handed), and
`image-watch` scans every base that the registry holds. A new member
is in the loop the morning after its first build.

The base's own `FROM` is `<REGISTRY>/alpine:3.22` — by TAG, against
the internal registry, on purpose. The seed cannot know the digest an
instance's `mirror-images` will give `alpine:3.22` there; the source
IS pinned by digest, in `images.txt`, and the build event records
what the tag resolved to as `base_digest`. The digest freezes the
filesystem the build starts from; the packages on top come from the
apk index of the day, which is the point.

### 3.2 The contract — what a consumer may assume

Asserted by the job BEFORE the image is pushed: a base that breaks
one of these lines fails its own build, not four tenant pods.

| a consumer may assume | why it is there |
|---|---|
| it runs as UID/GID **101** | tenant namespaces are PSS `restricted`; a numeric non-root USER is the only thing the kubelet can prove |
| it listens on **8080** | a tenant's NetworkPolicy admits `edge → 8080` only; an image on port 80 starts fine and never receives traffic |
| `/etc/nginx/conf.d/default.conf` is the `server{}` to replace | included INSIDE `http{}` by the base's own `nginx.conf`; it must keep `listen 8080` |
| `/usr/share/nginx/html` is the document root | `COPY --chown=101:101 dist/ /usr/share/nginx/html/` works unchanged |
| temp paths and pid live under `/tmp` | tenant pods run with a read-only root filesystem |
| logs go to stdout/stderr | Vector reads the pod's log; a file in the container is read by nobody |
| `STOPSIGNAL SIGQUIT` | nginx's graceful stop: in-flight requests finish |

It is nginx-unprivileged's contract, kept on purpose: every consumer
changed one `FROM` line and nothing else. A second member (another
server, another runtime) brings its own table here.

### 3.3 The tag scheme

```
aegis-base-<member>:<alpine-minor>-<build padded to 6>      e.g. aegis-base-nginx:3.22-000007
```

No floating tag — no `latest`, no `3.22` alone. Every build is a new
tag, and the consumer pins BOTH:

```
FROM <REGISTRY>/aegis-base-nginx:3.22-000007@sha256:…
```

The tag is for the human reading the Containerfile (which minor, which
build); the digest is what gets pulled and what Kyverno verifies. The
minor comes from the base's own `FROM` line, so bumping alpine is one
edit in one file.

### 3.4 `consumers.txt` — derived, not written

The block between the markers in `base-images/consumers.txt` is
DERIVED from the organization contracts by `aegis org apply`: the
`repo` of every service of type `estatico`, re-derived whole on every
run. A static front declared in a contract is a consumer of
`aegis-base-nginx` without anybody listing it; a service that leaves
the contract leaves the list.

After a successful build of a member, the job clones each consumer,
rewrites the `FROM` that names `aegis-base-<member>` to the new
`<tag>@<digest>`, and commits it to the default branch. That commit
is what makes the consumer's own pipeline rebuild on the patched
base. A repo whose Containerfile does not match leaves the run
UNSTABLE, with a metric and an event naming it
(alert `BasePropagationFailed`, §4); nothing else in the repo is
ever written.

---

## 4. What image-watch asks each morning

Every day at `H 6 * * *` — the cron is in the job-dsl, not in the
Jenkinsfile, so it exists the moment JCasC seeds the job and not
after somebody's first manual run — the watch asks four questions
about every mirrored image and every base aegis owns:

1. Against TODAY's vulnerability DB, does this image have a **fixable**
   CVE? (`--ignore-unfixed`: theoretical ones do not count.)
2. Did the **upstream tag** move since we pinned it, and does the
   candidate digest scan **clean**?
3. Which `trivyignore.yaml` exceptions **expire** within the month?
4. Could I actually **evaluate** this image today?

It never blocks anything. It pushes metrics and events, and for a
base aegis owns with a fixable CVE it fires `base-images` with those
members — the same morning. Third parties are NEVER re-mirrored on
their own: that is a human's decision, and the watch gives it the
three facts it needs.

The six alerts, and what to do:

| alert | severity | it means | what to do |
|---|---|---|---|
| alert `ImageWithFixableVulns` | warning, after 24h | a fixable CVE seen by the watch a day ago is still there. The 24h is the rebuild window: for a base the loop already tried | for an `aegis-base-*`: the distro has no fix yet or the rebuild failed — read the `base-images` console. For a third party: run `crane digest` on the upstream tag and read the next row |
| alert `UpstreamFixAvailable` | info | three legs on one image: it is vulnerable today, AND the upstream tag moved, AND the candidate scans clean. Only then does re-mirroring help | §2, steps 1-4. Until then `ImageWithFixableVulns` keeps firing for it |
| alert `ImageWatchCouldNotEvaluate` | warning | the watch could not scan this image (pull, transport, trivy). Its fixable count is not a measurement | read the `image-watch` console for the error. COULD NOT EVALUATE ≠ clean; the rest of the images ARE measured |
| alert `BasePropagationFailed` | warning | the base was rebuilt and signed, but this consumer's `FROM` was not bumped: what it deploys still stands on the old base, and nothing in its own pipeline will say so | `base-images` console for that repo; bump by hand if need be, then a build. The alert clears on the next rebuild that propagates |
| alert `TrivyIgnoreExpiring` | warning, 30 days' notice | an exception in `trivyignore.yaml` has under a month left | re-measure it (its statement says how it was justified and what would close it) or let it expire. Expired = the next mirror run and the next watch go red ON PURPOSE |
| alert `ImageWatchSilent` | critical | no heartbeat in 2 days: the cron is gone, the job is broken, or the push was rejected | the other alerts are MUTE, not green. Read the job; re-run it by hand; check the job-dsl still carries the cron |

What the watch publishes, so that a dashboard or a query can ask the
same questions without the alerts:

| series | one per |
|---|---|
| `aegis_image_fixable_vulns{image,severity}` | image and severity, against today's DB |
| `aegis_image_watch_failed{image}` | image the watch could not evaluate |
| `aegis_image_not_mirrored{image}` | line in `images.txt` with nothing in the registry |
| `aegis_upstream_moved{image}` | image whose upstream tag no longer points at our digest |
| `aegis_upstream_candidate_fixable_vulns{image}` | the candidate's own count |
| `aegis_trivyignore_expires_in_seconds{id}` | exception; negative = already expired; no series = no exceptions, which is health |
| `aegis_image_watch_timestamp_seconds` | run — the heartbeat |

`base-images` publishes `aegis_build_*{image="aegis-base-<member>"}`
like any build, plus `aegis_base_propagation_failed{image,repo}` and
`aegis_base_propagated_timestamp_seconds{image,repo}` per consumer.

Events, for the record vlogs keeps: source `jenkins-watch` emits
`watch-run`, `image-vuln`, `upstream-moved`, `ignore-expiring`,
`base-rebuild-triggered`; source `jenkins-base` emits `base-build`,
`base-propagated`, `base-run`. The mirror event keeps its `origen`
key: it is a log contract already ingested, and renaming it would
change the meaning of a year of records (glossary §5B).

---

## 5. What the loop does alone, and what it never does

Alone, without a human:

- re-scans every mirror and every base against today's DB;
- rebuilds a base aegis owns when it has a fixable CVE, asserts its
  contract, scans it with no exceptions, signs it, and commits the new
  digest into every consumer's `FROM`;
- says, per third party, whether re-mirroring would help — and only
  when it would (`UpstreamFixAvailable` needs all three legs);
- counts down every exception and goes red when one expires.

Never, and by design:

- **re-mirror a third party.** A new digest is a new image somebody
  else built; a human reads the scan and takes the two decisions of
  §2.
- **lower a severity, or reason about reachability.** The scan blocks
  CRITICAL/HIGH with a fix; that the fronts do not speak QUIC (§0) was
  a fact for the human, not a knob for the scanner.
- **add an exception to a base we own.** `trivyignore.yaml` is read by
  `mirror-images` only. A base that scans red is rebuilt, or it waits
  for the distro, and `ImageWithFixableVulns` says so every day until
  then. The exception path exists for a binary we cannot rebuild
  (postgres' `gosu`, with its symbol-by-symbol measurement and its
  `expired_at`), never for one we can.
- **deploy.** Nothing here touches a tenant's manifest. The base's
  propagation commits a `FROM`; the consumer's own pipeline, with its
  own scan of its own layer, builds and signs the app.

---

## 6. Handling a CVE by hand when the loop cannot

The loop cannot decide for a third party. When
alert `ImageWithFixableVulns` fires for one:

1. `crane digest <source>:<tag>` for the tag we pin AND the next
   candidate. Compare with `images.txt`. If `UpstreamFixAvailable` is
   also firing, the watch already scanned the candidate clean; if it
   is not, either the tag has not moved or the candidate is just as
   vulnerable — a new digest is not a new image.
2. If a clean candidate exists: edit the line (tag and digest), run
   `mirror-images`, bump the consumer. §2, exactly.
3. If it does not: the fix is not published upstream yet. Either wait
   — the alert stays, which is what it is for — or, for a CVE that is
   provably not in the binary, an exception in `trivyignore.yaml`
   with the measurement that proves it and an `expired_at`. An
   exception without a measurement is a CVE nobody looks at; one
   without an expiry is invisible debt.

And the case that started this protocol — a vulnerable base we do
NOT own, whose upstream has not rebuilt, whose fix the distro already
ships. The honest answer is that there is no exception path for it,
and there should not be one. The answer is to **own it**: a member
under `base-images/` (§3), `alpine + apk upgrade + apk add <package>`,
clean the same day the distro is, and in the loop from the next
morning. That is one Containerfile, and it was the only thing missing
on 2026-08-26.

---

## 7. Known gaps, named on purpose

**S11 — the watch scans bases and mirrors, not the app images that
actually run in tenants.** An app's image is base + its own layer,
and the watch never looks at the result. After a base rebuild, a
consumer whose OWN layer fails the scan stays on the old base while
the base's `ImageWithFixableVulns` clears: the base is clean, the
propagation succeeded, and what runs is still vulnerable.
The alert `BasePropagationFailed` covers the bump; the app's own build
failure is visible in Jenkins and in the `jenkins-build` events only. Closing
it means the watch enumerating what runs (the tenants' Deployments)
instead of what is listed — a different job, deliberately not this
one.

**Fan-out.** One base rebuild → N consumer commits → N app builds,
5000m each. Under the `jenkins-system` quota the pods QUEUE; they do
not fail. On a morning with a fix in the base every static front
rebuilds, one after the other, and the last one lands well after the
first. That is the cost of owning the base and it is paid in minutes;
the alternative was paid in days of red deploys.

**Silence is not health, and the guard is the guard.** Every alert in
§4 compares series the watch pushes; if the watch stops, they do not
go false, they go empty. `ImageWatchSilent` is the only thing that
sees that, and it is critical for that reason: with it quiet, the
other five are mute and the image nobody pushes to is, again, never
re-scanned.
