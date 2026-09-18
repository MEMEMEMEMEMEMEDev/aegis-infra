# Updating what this platform runs

aegis pins a version or a digest for everything it runs: fifty-odd
choices across six places, because the doctrine forbids a summary of
them — every pin lives only where it is consumed, and an index would be
a mirror with no consumer, which is drift with a nicer name.

That rule is right, and it left one question unanswerable: **what of all
this is behind, and by how much.** The vigía asks it every morning for
the seven mirrored images and for the bases aegis owns. The charts, the
images written by hand in the manifests, the pod templates of the CI,
k3s and the host's own binaries were nobody's job.

`aegis update` is that question, answered by measuring.

```bash
aegis update inventory      # what runs here against what exists upstream
aegis update plan           # what a window would raise, and how it undoes
aegis update status         # the last window
```

## What it measures, and what it refuses to guess

Every pin is **derived from the tree**, every time: the mirror list, the
`FROM`s of the images aegis owns and of its CI images, the
`targetRevision` of every Application, the `image:` written by hand in
the manifests and in the chart values, the pod templates of every
Jenkinsfile, and `k3s_version` plus the userland pins of the instance's
own `group_vars`. Nothing is listed here; adding a chart makes it appear
with no edit, and a class that comes back empty is a reader that broke
— check 206 says so rather than reporting «nothing to update».

Upstream is asked with the registry's own protocol (the same anonymous
token dance `aegis image` does), with the chart repository's index, and
with the releases of the projects that publish binaries. Four answers,
and the fourth is why this is careful:

| answer | what it means |
|---|---|
| **al día** | the pin is on the newest candidate |
| **atrasado** | there is a newer one, named |
| **desaparecido** | the pinned tag no longer exists upstream |
| **no medible** | unreachable, rate-limited, or a tag scheme nobody can order |

A newer candidate has to carry the **same shape**: `3.22` is a series
and `3.24.2` is a point release of another one, so the second is never
offered to somebody who pinned the first. A tag with a build number and
a git hash in it — `3355.v388858a_47b_33-23` — is reported as
**unorderable**, because sorting it is inventing an order the publisher
never promised, and a window that acts on an invented order updates to
something nobody chose.

**A class nobody could measure makes the command exit 2.** «Upstream did
not answer» is never «up to date».

## The layers, and how each one comes undone

`aegis update plan` puts every proposal in a layer, and says beside it
what it would take to undo it. The order is the one a window follows:
the ground first, what stands on it after.

| # | layer | how it is undone |
|---|---|---|
| 1 | the host's packages | nothing: a package installed is not uninstalled inside a window |
| 2 | the host's binaries | revert the pin and re-run phase 05 |
| 3 | k3s | revert and re-run phase 20, best effort |
| 4 | the platform's charts | revert and sync |
| 5 | the images written by hand | revert and sync |
| 6 | the mirrored images | revert the commit; the registry keeps the previous digest |
| 7 | the bases aegis owns | revert and rebuild, which re-propagates |
| 8 | the CI's pod templates | revert |

## What it refuses, out loud

- **A major jump** is never taken by a window: it carries migrations git
  does not undo. It is proposed, refused by name, and waits for a human
  who has read the release notes.
- **A minor of k3s** rewrites the service's `ExecStart` and the node
  re-registers under another name. Same treatment.

A proposal that hid what it will not do would not be a plan.

## Why the round had to learn to read the probes

One of the three legs a window accepts on is «every public site
answers». Until 2026-09-18 the round counted that each organization with
a domain HAD a blackbox probe and stopped there: a tenant returning 500
to every customer passed, because the probe existed. Counting watchers
is not watching.

It now reads what the probes see, and tells three things apart: a site
that does not answer at all, a site that answers with a redirect the
module refuses on purpose (its own login, or Cloudflare Access), and a
site that answers. The middle one is a notice and not a failure —
collapsing it into «down» would make the line permanently red on any
instance with a tenant behind Access, and a signal that never changes is
a signal nobody reads.

## What is not here yet

The window itself: the snapshot, the maintenance page, the layers
applied one at a time with their acceptance, and the rollback that runs
by itself when the acceptance fails. This document grows with it.

Tenant application images are outside all of this, as they are outside
the vigía: that gap is named in `images.md` §7 and is not closed here.
