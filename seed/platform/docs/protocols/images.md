# Protocol: images — mirrors, owned bases and the daily watch

Status: **contract v1**. This document defines what an operator touches
when a container image enters the platform, when one of them turns out
to be vulnerable, and what the platform does about it on its own every
morning. What changes over time are the LISTS (`images.txt`,
`base-images/`, `consumers.txt`) and the exceptions
(`trivyignore.yaml`), not this contract.

Audience: the operator of an aegis instance, and the developer who
needs a runtime the platform does not serve yet. You do not have to be
the author of aegis to read it. If you came here to ask for an image,
[§2](#2-asking-for-an-image) is one command and you can stop reading
after it; if an alert named below woke you,
[§4](#4-what-image-watch-asks-each-morning) says what it means and what
to do; if what you need is a base aegis builds itself,
[§3](#3-owning-a-base).

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

There was a third hole, of a different kind, and it took a year to be
named because it never broke anything: asking for an image was five
manual steps. Read the protocol, measure the digest with `crane`, edit
the list, fire the job from Jenkins' console, type the `FROM` from
memory. Five places to be wrong, and being wrong in the last one is
expensive in the worst way — the build STARTS, and dies later, further
away, in somebody else's pipeline. §2 is those five steps with the hand
taken out.

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
   trivyignore.yaml               UID of its USER · 8080        (no scan, no sign:
   scoped exceptions)             nginx -t · node -e             nothing runs in
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
| `mirror-images` | third parties the tenants run (postgres, redis, garage, runtimes) | blocking, with the scoped exceptions of `trivyignore.yaml` | yes, by digest | phase 80 once; `aegis image request` whenever somebody asks for an image |
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

## 2. Asking for an image

```
aegis image request <repo>:<tag>
```

One command, and it is the whole procedure. It resolves the source (a
bare `python:3.12-slim` comes from the public path the list already
uses for the official images; a reference that carries a registry is
taken as written), MEASURES the digest that tag points at today,
declares the line in `mirror-images/images.txt`, commits it, **pushes
it**, fires `mirror-images` and waits. What it prints, when the scan is
green, is the one line the build will demand:

```
FROM registry.registry-system.svc.cluster.local:5000/python:3.12-slim@sha256:...
```

The platform does not choose versions for anybody. Three Pythons are
three lines, and which three is the developer's business. What the
platform owes is the other half: fix the digest of what was asked for,
scan it, sign it, and hand back the exact reference — so that being
wrong about it is impossible rather than merely discouraged.

The push is not bookkeeping. `mirror-images` is a pipeline-from-SCM: it
clones the platform repo at branch `main` and reads `images.txt` out of
THAT checkout, so a commit that stays on the local disk is an edit the
job never sees. The job would then re-mirror the previous list, end
SUCCESS, and the command would go looking in the registry for something
nobody was ever asked to mirror. The push is verified, and so is the
result: the command does not fire the job until the remote branch it
builds from contains the commit.

**Running it twice writes nothing.** If the line is already declared at
that digest and the registry serves it mirrored and signed, the command
prints the same `FROM` and leaves: no edit, no commit, no build. That
is not a convenience. It is what makes the command safe to put in a
README, in a runbook and inside a script.

### The three outcomes

| what happened | what it does | rc |
|---|---|---|
| declared at this digest, mirrored and signed | prints the `FROM`; nothing written, committed or built | 0 |
| new, or declared and not yet served | declares it, commits, pushes, fires `mirror-images`, waits, prints the `FROM` | 0 |
| the **upstream tag moved** | stops, showing the declared digest and today's | 1 |
| the **scan went red** | does NOT mirror: lists the blocking findings and names the two ways out | 1 |

**Upstream moved.** A new digest is not a new image (§0), and following
one is a decision the platform does not take on its own: `--bump` is a
person saying yes. Before saying it, the watch already knows whether
the candidate is any cleaner — alert `UpstreamFixAvailable` fires only
when the image is vulnerable today AND the tag moved AND the candidate
scans clean.

```
aegis image request python:3.12-slim --bump
```

**The scan went red — and first of all, on what.** The job mirrors and
scans EVERY entry of `images.txt` on every run and fails at the end with
the list of what broke, so a red build is not by itself evidence about
the image you asked for. The command reads the console for the entries
that actually failed before it says anything:

- your image is among them: the findings are reported from ITS block of
  the console, and the exception, if you write one, is scoped to the
  scan targets of that block;
- your image is not among them: it says so, names the entries that did
  fail, and refuses `--allow` outright. An exception written there would
  be scoped to another image's finding and would carry your measurement
  under a binary you never looked at. Those entries are their own
  requests, with their own measurements.
- the console names no failing entry at all: the build died before the
  per-image loop, nothing is attributed to anybody, and the last lines
  of the build are printed instead.

If your image was mirrored and signed in that same build, you get its
`FROM` and exit 0, with a warning that `mirror-images` stays red for the
others — the platform's red belongs to `aegis image check`, not to
somebody else's request.

When it IS your image, the gate worked, and it worked in the right
order: the scan runs BEFORE the push, so nothing entered the registry.
There are exactly two honest ways out.

1. A newer tag. The command lists the ones upstream publishes above
   this one with the same shape, when it can read them; whether one of
   them is the right one is not something a sort can know.
2. A dated exception, and only for a CVE you have MEASURED is not
   reachable in this binary:

```
aegis image request postgres:17.10-alpine \
    --allow CVE-2026-33818 --until 2027-02-28 \
    --reason "encoding/asn1 is not linked into the binary (0 symbols)"
```

The three flags travel together because an exception is three things at
once: the CVE, the measurement that justifies it, and the day the
measurement stops holding. It is written into `trivyignore.yaml`,
scoped to the exact scan targets the console reported (never a
wildcard), and the job is retried ONCE. A second red means the
exception did not cover what was blocking, and retrying again would
only be a loop with a file growing inside it.

There is no `--force`, and there will not be. A third way out would
only be a way of not looking.

### The rest of the surface

| command | answers |
|---|---|
| `aegis image list` | what is declared, crossed against the registry: name, tag, short digest, mirrored, signed, live exception with its expiry |
| `aegis image from` | ONLY the `FROM` line of something already mirrored, so a generator or a template can consume it. Nothing on stdout when it is not there, and a non-zero exit code |
| `aegis image check` | everything declared is mirrored and signed; whatever is not comes with the command that fixes it |
| `aegis image gc` | what the registry is keeping that nothing fixes, declares or runs — the plan only, until `--yes`. §8 |

`AEGIS_IMAGE_DRY_RUN=1` makes `request` and `list` explain what they
WOULD do and touch nothing: no cluster, no registry, no git, no build.

On the word **signed** in `list` and `check`: what those two measure is
that the registry holds the signature object cosign publishes for that
digest. The cryptographic verification happens where the key already
is — Kyverno at admission, and the `from-guard` stage below at build
time. Two different facts, and saying so is only honest if it is
written down.

### What is still not the command's to do

**Bumping the consumer.** Mirroring does not deploy. For a platform
type that is `services.yaml` (its digest is the INTERNAL registry's,
not the source's — a `crane copy` of a multi-arch index does not
preserve it) followed by `aegis org apply`; for an app it is the `FROM`
in its repo, which is the line `request` just printed. Pulling a new
image and putting it in production are two decisions, taken by the same
person but not in the same moment.

**The comment above the line.** The command writes the declaration; it
cannot write why THIS image and not the obvious alternative, or what
its known limits are. The file's existing entries are the model, and a
line without its reason is the first thing a stranger cannot maintain.

### The guard at the other end

A `FROM` printed here is worth exactly what the build does with it, so
the tenant pipeline stops taking the Containerfile's word for it. The
`from-guard` stage of `Jenkinsfile.app` — between `detect-change` and
`build`, so a manifest-only commit does not pay for it and nothing is
extracted before it runs — reads every `FROM` of the service's
Containerfile and, for each one that is not a reference to an earlier
stage of the same file, demands four things: the internal registry, a
digest, an image the registry actually serves at that digest, and a
signature that verifies against the aegis key. When one is missing the
build dies with the sentence that is also the instruction:

```
FROM <ref> is not mirrored/signed. Run: aegis image request <ref>  and paste the FROM it prints
```

During init phases 50-70 the cosign key does not exist yet, so the
signature half CANNOT be measured. It is not skipped quietly: the stage
says so, the event carries it, and the existence half still runs.

The two ends are one property — nothing runs in a tenant that the
platform did not scan and sign — and check 147 holds both: the seed's
own Containerfiles by static reading, every organization's by that
stage.

---

## 3. Owning a base

A base is an image aegis BUILDS from the distribution's packages
instead of mirroring somebody's build of them. It is the answer to
§0: when the distro ships the patched package, one `apk upgrade`
picks it up, on our cadence, not a third party's.

### 3.1 A member

```
base-images/
  consumers.txt          ← every repo that builds an image (derived block, §3.4)
  nginx/                 ← one directory per member: the static fronts' base
    Containerfile        ← FROM public alpine:3.22@sha256:… + apk upgrade + apk add nginx
    nginx.conf
    default.conf
    index.html
  node/                  ← the node backends' base
    Containerfile        ← same FROM + apk upgrade + apk add nodejs; nothing else to ship
```

Two members, same day, same cause. `nginx/` is what §0 tells. `node/`
came hours later: the same CVE-2026-14456 was found in the `libssl3t64`
of `nodejs-distroless:22` (Debian 13), the mirrored runtime the four
node backends stood on, and the upstream candidate digest was measured
the same morning: **not patched either** — a new digest is not a new
image, the second time in a day. Alpine 3.22 already shipped the fixed
openssl, so the answer was the one §6 prescribes: own it.

To add a member: a directory under `base-images/`, a `Containerfile`
in it that honours the contract below, and a comment at its top that
says what consumers it exists for. Nothing to register: `base-images`
builds every directory it finds (or the `MEMBERS` it is handed), and
`image-watch` scans every base that the registry holds. A new member
is in the loop the morning after its first build.

The base's own `FROM` is the **public** `alpine:3.22`, pinned by
**digest** — not the mirror, on purpose. Measured on 2026-08-27: the
public image was built on 2026-06-22 and still carried the libcrypto3
the mirror's blocking scan refuses, so a base that exists to run
`apk upgrade` on top of it could never be built from a mirror it
cannot enter. Nothing is lost: the alpine underneath never runs
anywhere — its packages are replaced on the next line, and what runs
is the result, scanned with no exceptions and signed. A public digest
is universal, so the seed can pin it and every instance builds from
the same bytes; the build event records it as `base_digest`. A bare
tag from the internet is what check 138 refuses. The digest freezes
the filesystem the build starts from; the packages on top come from
the apk index of the day, which is the point.

### 3.2 The contract — what a consumer may assume

Asserted by the job BEFORE the image is pushed: a base that breaks
one of these lines fails its own build, not four tenant pods. The job
reads the uid it expects from the member's own last `USER` line — it
must be numeric and non-root, and it is what the pushed image's config
must carry — and the port from the contract (8080, every member). Each
member also RUNS its server once at build time, so the class of error
that only a running binary can find surfaces in the base's build and
not in a consumer's pod: `nginx -t` for nginx, `node --version &&
node -e '…'` for node. Check 138 demands both, per package installed.

#### aegis-base-nginx

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
changed one `FROM` line and nothing else. The second member did the
same with the contract IT replaced.

#### aegis-base-node

| a consumer may assume | why it is there |
|---|---|
| it runs as UID/GID **65532** (`nonroot`) | distroless's uid, kept so the four backends change only their `FROM`; numeric, so PSS `restricted` can prove `runAsNonRoot` |
| `ENTRYPOINT ["/usr/bin/node"]` — the consumer's `CMD` is the script path, `CMD ["/app/src/server.js"]` | distroless's contract: the backends already write it this way, and a `CMD` that is a path cannot be a shell |
| `WORKDIR /app` | `COPY --chown=65532:65532 . /app/` works unchanged; relative paths in the code resolve from there |
| it listens on **8080** | the same NetworkPolicy as the fronts: `edge → 8080` only |
| `NODE_ENV=production` | libraries drop their development paths; a consumer that needs otherwise sets its own |
| there is no `npm`, and nothing to install with | consumers copy a `node_modules` built in CI on `aegis-ci-node` — the same **22.23** line, **musl** (`node:22.23.1-alpine`) — so a native module built there loads here. Installing in the runtime image is the base you cannot rebuild, again |

The build-time check is `RUN node --version && node -e '…'`: the
runtime loads and the core modules are in the package, proven on the
base's build and not on the first request to a backend. It is the
sibling of `nginx -t`, and it is the line check 138 refuses to let a
member that installs `nodejs` leave out.

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
`repo` of **every service that builds an image** — every image-bearing
type, not only `estatico` — re-derived whole on every run. A service
declared in a contract is on the list without anybody listing it; a
service that leaves the contract leaves the list. Until 2026-08-27 it
was the static fronts alone, because nginx was the only base. With two
bases the contract cannot say which one a repo stands on — only its
Containerfile can — so this is ONE list for every base, and the job
sorts it out per member.

After a successful build of a member, the job clones each listed repo
and greps it for a `Containerfile` whose `FROM` names
`aegis-base-<member>@sha256:` (with or without a tag before the `@`).
Found: that line is rewritten to the new `<tag>@<digest>` and committed
to the default branch — the commit that makes the consumer's own
pipeline rebuild on the patched base. Not found: the repo is **skipped
with a notice** in the console. A listed repo that names no member is
a fact — an API on a mirrored runtime, a front not yet moved — and
not a failure. What IS a failure is a repo that names the member and
could not be bumped (clone, sed, push): that leaves the run UNSTABLE,
with a metric and an event naming it
(alert `BasePropagationFailed`, §4); nothing else in the repo is ever
written.

Over-listing costs one clone and one grep. The hole the list closes
is the other direction: a consumer that is **not** listed is the
`FROM` nobody bumps — the base's alert `ImageWithFixableVulns` clears,
the propagation reports success, and what runs still stands on the
old base. That is why the block is derived and never written by hand.


### 3.5 A repo that arrives pinned by another installation

§3.4 solves the propagation **inside** one installation: a base is
rebuilt here, and the job rewrites the `FROM` of every consumer here.
The other direction has no job and cannot have one — a repo that comes
from somewhere else, or that is being brought up on a fresh
installation, carries pins that were measured in a registry that is not
this one:

```
FROM <REGISTRY>/aegis-base-nginx:3.22-000001@sha256:394ed28…
```

Both halves of that line are wrong here, and each for its own reason.
The **digest** was born in the other installation's registry — the same
bytes get a different name inside, because `crane` rebuilds the
manifest as it copies — so this registry has never heard of it. The
**tag** may be wrong too: a base's build number is born in the registry
that builds it (§3.3), and the installation that produced the line
above was on its first build while this one is on its fourth. The
`from-guard` stage refuses the build, correctly: nothing of that image
passed through this installation's scan or its key.

```
aegis app rebase <org> --check     # what it would repoint, touching nothing
aegis app rebase <org>             # repoints it; the push stays yours
```

It checks out every repo of the organization — the list is the
generator's `repos_of`, the same one the Applications and the
AppProject's `sourceRepos` come from — finds the Containerfiles by
looking rather than by path, and rewrites **only** the `FROM`s that
name the internal registry. A public `FROM` is left alone: whether it
may be built from is the `from-guard`'s business and it is a different
problem.

**Where each half of the new reference comes from**, and neither is
written down in the product:

- the **digest** is `aegis image from <name>:<tag>` — the only command
  that knows the internal digest, and the only one that refuses an
  image that is present and **unsigned**. A table of digests in the
  product would be a second place for the truth to live, and the stale
  one is always the cheaper to read.
- the **tag** is derived from whichever artifact owns it. For a
  mirrored third party that is `mirror-images/images.txt`: which
  python, which alpine, is a declaration, and the repo's old tag does
  not get a vote. For a base the platform builds it is the registry
  itself, through `aegis ci digests`: the alpine minor the repo names is
  **kept** — a rebase does not move anybody from the 3.21 line to 3.22
  — and only the build number, the part born in this installation, is
  re-derived to the highest one served.

It writes files and it does **not** commit and does **not** push. That
is the same line §2 draws for `aegis image request`: pulling an image
and putting it in production are two decisions. The command prints the
exact `git -C … commit && git -C … push` per repo and stops there.
`--check` goes further and leaves nothing at all behind, not even the
checkout.

Check 175 holds the verb: it exercises the rewriter over a
Containerfile of every shape (internal, public, a stage reference, a
commented one) and the tag derivation over both families, and it fails
if the reference stops coming from `aegis image from`, if a digest
appears written into the product, or if the verb ever pushes.

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
| alert `ImageWithFixableVulns` | warning, after 24h | a fixable CVE seen by the watch a day ago is still there. The 24h is the rebuild window: for a base the loop already tried | for an `aegis-base-*`: the distro has no fix yet or the rebuild failed — read the `base-images` console. For a third party: §6, which starts by asking the command again |
| alert `UpstreamFixAvailable` | info | three legs on one image: it is vulnerable today, AND the upstream tag moved, AND the candidate scans clean. Only then does re-mirroring help | `aegis image request <repo>:<tag> --bump`, then bump the consumer (§2). Until then `ImageWithFixableVulns` keeps firing for it |
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
  else built. `aegis image request` refuses a moved tag and says so;
  `--bump` is a person taking the decision, and bumping the consumer is
  the second, separate one (§2).
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
- **let a `FROM` through on trust.** Neither a human nor the loop
  decides that a base is fine because it looks fine: the `from-guard`
  stage asks the registry and the key, on every build, and a build that
  cannot answer does not build (§2).

---

## 6. Handling a CVE by hand when the loop cannot

The loop cannot decide for a third party. When
alert `ImageWithFixableVulns` fires for one, the first move is to ask
the command again for the same thing:

```
aegis image request <repo>:<tag>
```

and read which of the three outcomes of §2 comes back.

1. **It prints the `FROM` and exits 0.** Upstream has not moved and
   what we serve is what we declared. The CVE is real and there is no
   fix to pull: the alert stays, which is what it is for, and the
   decision is between waiting and step 3.
2. **It says the tag moved.** A candidate exists. If
   alert `UpstreamFixAvailable` is also firing, the watch already
   scanned that candidate clean this morning and `--bump` is the whole
   fix; if it is not firing, the candidate is just as vulnerable — a
   new digest is not a new image, and re-pinning would buy nothing but
   a different sha. After a `--bump`, bump the consumer: two decisions,
   §2.
3. **Neither of those.** The fix is not published upstream. Either wait
   — the alert stays, which is what it is for — or, for a CVE that is
   provably not in the binary, write the exception with the measurement
   that proves it and the day it stops holding
   (`--allow`/`--until`/`--reason`, §2). An exception without a
   measurement is a CVE nobody looks at; one without an expiry is
   invisible debt. It goes in `trivyignore.yaml`, entry by entry and
   never by wildcard, because that is what keeps it from growing on its
   own: a sixteenth CVE on the same path BREAKS the build and somebody
   has to redo the measurement.

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
one. What the `from-guard` stage (§2) narrows is the other end of the
same gap: an app can no longer build on a base that is outside the
loop, so «what the watch does not look at» and «what the platform
serves» stopped being two different sets.

- **The platform's own node consumer is in the loop too.** The bucket
  provisioner Job (`bucket.aprovisionador` in `services.yaml`) stands on
  `aegis-base-node` since 2026-08-27. It is not a tenant repo, so it is
  not in `consumers.txt`: the `base-images` job treats the platform repo
  as an implicit consumer and rewrites the `tag:` and `digest:` lines of
  that block after every successful build of the member. The Job is an
  ArgoCD sync hook recreated on every sync, so the next sync runs it on
  the rebuilt base — and the bump ALONE does not cause that sync:
  hooks sit outside the desired-state comparison, so an app whose only
  change is a hook's image stays `Synced` and auto-sync never fires
  (measured 2026-08-27 on the reference instance). After a rebuild of
  `aegis-base-node`, run `aegis sync garage` (or wait for the next real
  change under `garage-system/`); the Application's `operationState`
  records the hook's phase, which is the proof. The seed carries a SAMPLE tag+digest (a digest born
  in a registry cannot be known before phase 80 builds it there); check
  138 holds the shape, phase 80 and the job hold the value.

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

## 8. Pruning: what the registry keeps, and what it lets go

The registry stored every image that was ever built and nothing pruned
it. Measured on 2026-09-01: the GPU engine costs about 5.6 GB
compressed per build, so **two rebuilds occupied 11.2 GB**; deleting
the manifests through the registry's API and running
`registry garbage-collect --delete-untagged` inside the pod brought it
back to **3.5 GB**. It had to be done by hand three times that day, and
one of the images deleted had never even started.

The cost is not the disk on its own. It is that the same disk has to
hold the **~42 GiB of ephemeral storage** the build of that engine
needs on the node, and the kubelet starts evicting pods below roughly
**11 GiB free**. So every rebuild made the next one likelier to be
evicted, and the symptom said nothing about a disk: the pod was
`Evicted` and the pipeline said `ABORTED`, twenty minutes in. Phase 87
refuses a build that does not fit before it fires it (check 171); this
is the other half — the reason the room ran out.

```
aegis image gc                    # the plan, and nothing else
aegis image gc --yes              # delete the candidates and collect the blobs
aegis image gc --keep 4 --repo aegis-ai-vllm
```

### It says before it does

`gc` prints its plan and stops. Every row carries a verdict, the tags,
the size and the reason, and nothing is deleted until somebody types
`--yes`. There is no `--force` and no environment variable that flips
it: the two states of this command are *explain* and *act*, and only a
person moves it from one to the other.

### What protects an image

Three facts, each read from where it is true, and **any one of them is
enough**:

| source | question it answers | why it cannot be dropped |
|---|---|---|
| the instance's manifests | what does this platform fix by digest? | a digest written in a manifest is in use even if its tag is a year old — that is what pinning by digest means |
| `mirror-images/images.txt` | what does the platform promise to serve? | `aegis image check` says every destination of that list is mirrored and signed; pruning one would make it break its own promise |
| the live cluster | what is running right now? | the tenants' overlays live in the ORGANISATIONS' repositories, not on this disk. Without this question the image of a pod serving traffic is a candidate |

All three are derived, never listed. The manifests are scanned with
their comments stripped — this tree argues every decision beside the
code, so the file that pins a digest is also the file whose prose
quotes the digest it used to pin — and a scan that fails takes the
command down with it rather than returning an empty protected set. If
the cluster does not answer, the command stops: that answer is not
«nothing is running», it is «I could not look».

### The retention policy, and why the number is 2

**Default `--keep`:** 2

On top of everything protected above, the newest N images of each
repository survive on age alone. The argument for N = 2:

- what a **rollback** needs is two digests: the one deployed and the
  one it replaced. A third is not a rollback, it is history.
- the arithmetic of the repository that actually hurts. The GPU engine
  is ~5.6 GB per build here; N = 2 is ~11.2 GB for that one repository,
  which is the measured number that left the node at the eviction
  floor. N = 3 would be ~16.8 GB — more than the kubelet's floor
  itself, spent on an image nobody is going to roll back to. Before a
  heavy build, `--keep 1` is the honest setting.
- it is a **floor, not a ceiling on safety**: a digest the instance
  fixes or the cluster runs is kept whatever N says. N only decides how
  much history survives on age alone.

Age is read from the date the image itself carries, not from its tag.
The tags in this registry are `main-000012`, `vllm0.11.2-9f3a1c` and
`2.1-260827`; no sort orders those three together, and an image the
registry cannot date is not a candidate at all — «I do not know how old
this is» is not a reason to delete something.

### The signatures are part of the image, and `--delete-untagged` does not collect them

cosign publishes the signature of `<digest>` as a **tag**,
`sha256-<hex>.sig`, in the same repository. From the registry's side
that is a *tagged* manifest, so the collector marks it live and leaves
it — and its blobs — exactly where they are. Deleting an image without
its companion therefore frees less than it looks like and leaves a
signature of nothing behind.

So `gc` deletes the companions itself, in the same pass, derived from
the digest being pruned (`sha256-<hex>.*`, which covers `.sig` and any
`.att`/`.sbom` that may appear), and the same rule picks up the ones
already orphaned by the hand-pruning of 2026-09-01. `--delete-untagged`
is still what frees the *blobs*: deleting a manifest through the API
only unlinks it.

### The two hazards it refuses to walk into

- **A push in flight.** The collector sweeps the blob store while the
  registry keeps serving it, and a blob uploaded during the sweep can
  be freed before the manifest that references it is written. `gc`
  refuses to act while any Jenkins job is building, and names them.
- **A 2.x collector.** distribution 2.x did not mark the
  per-architecture manifests an *index* references, so
  `--delete-untagged` could strip the children of a mirrored
  multi-architecture tag. 3.x marks them; the platform pins 3.1.1 in
  `k8s/base/registry-system/registry.yaml`, and `gc` reads the version
  of the registry that is actually running before it sweeps.

### What it measures

`du` over the storage root the running registry's own config declares,
before and after, and the difference is what it reports. The registry's
API can add up the blobs it knows about; only the filesystem knows what
the collector actually removed.
