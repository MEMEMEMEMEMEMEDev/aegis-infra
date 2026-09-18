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

## Before a window may open

```bash
aegis update window              # dry: everything that refuses is asked, nothing runs
aegis update window --yes        # the window
aegis update rollback            # undo the last window's commits
```

`window` collects **every** reason to stop before it touches anything,
and prints all of them at once. An operator who fixes one refusal and
runs again only to meet the next is being made to discover the list one
night at a time.

| refusal | why it stops the window |
|---|---|
| `platform-dirty` | a window commits file by file. Work already in the tree would ride into a commit the rollback then reverts |
| `platform-unpushed` | the cluster converges on the remote. The acceptance would measure a platform nobody deployed |
| `platform-untracked-branch` | with no upstream nobody can say whether what is here has been published |
| `maintenance-half-configured` | a way in with no way out, in either direction |
| `budget-too-small` | a window that runs out of time between two layers is the shape this protocol exists to prevent |

And then the photo, which is a refusal of its own kind: **with no
before there is nothing for a rollback to come back to.** If the round,
`verify` or the inventory cannot be taken, the window closes there,
having run no hook and left no directory behind. That last part
matters: `aegis update status` reports on windows that happened, and a
window that never opened did not happen.

Nothing runs without `--yes`. Same rule as `aegis destroy`.

## The maintenance page is yours, and its effect is measured

Two orders in `aegis.conf`, and aegis knows nothing about what is
behind them:

```bash
MAINTENANCE_ON="cd ~/maintenance && npx wrangler deploy"
MAINTENANCE_OFF="cd ~/maintenance && npx wrangler delete --force"
```

A Worker, an nginx `return 503`, a DNS change, a script that flips a
flag: the product only needs the first to take the public sites off the
air and the second to undo exactly that. **Both empty is a complete
answer**, and then the window runs with the sites live and says so out
loud in its own document.

What the product does insist on is proof. After running
`MAINTENANCE_ON` it takes the round again and asks whether any reading
that was fine has stopped being fine. If nothing changed, the hook did
not do what it says, and the window **stops there having changed
nothing** — a maintenance page nobody can see is worse than none at
all, because it is the false belief that the sites are shielded.

It asks that question through the round and not by grepping the round's
prose: on an instance whose contracts declare no domain there is
nothing to take off the air, and that is reported as «the effect cannot
be read», not as «no effect».

## Jenkins goes quiet

```bash
aegis ci quiet on | off | status
```

Every commit a window makes is a push, and Jenkins hears every push. A
build that starts halfway through the charts builds an image out of a
tree that is half the old version and half the new one — and it says
SUCCESS, which is the worst kind of artifact, because nothing about it
looks wrong.

Quiet mode is not a pause: what is running runs to the end and the queue
simply stops being consumed. The state is read from Jenkins itself
every time, never remembered on the host — a flag kept here would be
the one thing to disagree with the machine on the morning after a
window that died halfway.

## «No new failures», defined

The acceptance compares two rounds. The key is the section plus the
**shape** of the measure's sentence, with digits, hexadecimal and
durations flattened, because the round narrates with live numbers in it
and comparing those literally would call every measure new.

A **new failure** is a reading that is bad now and was not bad before,
**or one that was fine before and that nobody could measure now.** The
second half is the one that is easy to leave out and the one that
matters most: a window that blinds a measurement has not passed it, it
has stopped asking. A reading that disappears from the round entirely
counts the same way.

What already came in broken is listed apart and does not block. Holding
a window hostage to a fault that predates it means the instance never
gets updated at all.

## The way back

`aegis update rollback` walks the window's commits **newest first** —
two commits touching the same file only revert cleanly in the reverse
of the order they were made — and uses `git revert`, never `reset`: the
history of a window is evidence, and an instance whose way back is
«pretend it never happened» cannot answer what it did last month. It
also keeps the remote a fast-forward, so the rollback is an ordinary
push and never a force.

A commit that does **not** revert cleanly stops the walk and says so.
Reverting past a conflict would leave the tree in a state neither the
window nor the operator ever described.

Afterwards it compares the **tree** against the photo, not the commit:
after a rollback the HEAD is necessarily a different commit, and the
only honest question is whether the content is the same.

All of this is exercised by check 207 on a real copy of the seed's
platform in a throwaway directory, with the very functions the window
calls — including a commit made to conflict on purpose. A way back that
only exists in a test double is a way back nobody has walked.

## The host's binaries now prove their bytes

https authenticates the server, not the artifact. Until 2026-09-18
every binary of the host arrived over https and was installed exactly
as it came down; helm arrived through `curl | bash` of a script off the
**main** branch of its own repo.

Each of the five now downloads its publisher's checksum file
separately and compares before installing, and a mismatch deletes the
download and stops the phase. A tool that is not downloaded by aegis is
installed by apt, and apt's repository signature is its proof — which
is why `apt` is a legitimate value of a pin, and why a tool that falls
to apt **must** be pinned `apt`: a number beside it would be a promise
nobody keeps, and `aegis update` would read it, measure it against
upstream and propose a bump the phase has no way to install.

`sops` changed shape for this: the `.deb` it publishes is not covered
by its signed `checksums.txt`, so the binary that is covered is what
gets installed. `age` went the other way and is now pinned `apt`,
because apt installs whatever the distribution's line carries and no
number written here was ever going to change that.

Inside a window the phase runs with `AEGIS_HOST_ALIGN=1`, where drift
is not a question but the job: it installs the pin instead of opening a
RED nobody is awake to answer, and then reads the version back off the
binary that answers on PATH. A window that reports a bump while the
host still runs the old one is the most expensive thing this protocol
could do.

## The three things the window changes about the machine

Not the tree: the machine. Each one is right while the window runs and
is silent damage afterwards.

| what | why | who puts it back |
|---|---|---|
| Jenkins in quiet mode | every commit is a push, and a build started on a half-changed tree says SUCCESS | the restore stack |
| the alerts about the sites, silenced | the maintenance page makes «the site does not answer» true on purpose | the restore stack, **and** an expiry of its own |
| the backup clock, stopped | a backup taken mid-window captures a half-updated instance and calls it the day's copy | the restore stack |

Every one is pushed onto a stack **before** it is done, and the stack is
run in the exit path of every ending there is — accepted, rolled back,
needs-a-human, and the exception nobody predicted. One undo that fails
does not stop the others: tidiness is not worth leaving the rest of the
machine as the window left it.

The silences carry an expiry of their own, one hour past the budget. The
stack is the first line of defence and the expiry is the second, and a
protocol that leans on only one of the two eventually meets the day that
one failed.

**The heartbeat is never silenced.** `DeadmanAegis` is the alert that
fires when the alerting itself stops working, and a window is exactly
when that would be easiest to miss.

## The nine layers

Ground first, what stands on it after. After each one the round is taken
again and **only that layer's sections** are compared: judging a layer
by the whole round would make every layer answer for a fault the one
before it left behind, and the walk would stop in the wrong place —
which is worse than not stopping, because the rollback would then undo
something that was not the cause.

| # | layer | judged by | ~min |
|---|---|---|---|
| 1 | the host's packages | node, pods | 20 |
| 2 | the host's binaries | node, supply chain | 15 |
| 3 | k3s (patches only) | node, pods, argocd | 25 |
| 4 | the platform's charts | argocd, stuck syncs, pods, certificates | 60 |
| 5 | the images written by hand | pods, argocd | 25 |
| 6 | the mirrored images | supply chain | 30 |
| 7 | the bases aegis owns | supply chain, CI quota | 45 |
| 8 | the CI's pod templates | every push built, CI webhooks | 20 |
| 9 | the kernel and the driver | node | 20 |

Check 213 joins the two lists that must not drift: every class of pin
the inventory can produce is owned by exactly one layer, and every
section a layer is judged by is a section the round actually has. A
layer naming a section that no longer exists does not go red — its
acceptance compares an empty set and passes **always**.

Three of them are worth reading twice:

**Layer 1 has no way back.** `apt-get install --only-upgrade` cannot be
undone inside a window; downgrading a distribution package is not an
operation, it is a project. So the protection is not a rollback, it is a
refusal: the layer does not run at all if the round came in with
failures. Raising the floor under an instance that is already broken
removes the one thing that made the breakage diagnosable, which is that
nothing else had changed.

**Layer 4 goes one chart at a time,** each rendered with `helm template`
before a line is written, then committed, pushed, synced, and waited on
until Synced **and** Healthy. That is why it costs an hour. Six charts
raised in one commit and a cluster that goes unhealthy afterwards is six
suspects; six commits with a wait between them is one. And «Synced»
alone is not acceptance: it means git and the cluster agree about the
manifests, and says nothing about whether what came up works.

**Layer 9 installs and never reboots.** A reboot takes the instance down
for minutes and brings it back in a state nothing here has measured. It
is a decision with a human in it; the window leaves it ready and says
so.

Layers 6 and 7 build, so Jenkins comes out of quiet mode for them and
goes back in afterwards. The restore stack still holds the way back, so
a window that dies there does not leave the CI open on a half-changed
platform.

## The budget

Four hours by default, and the only thing it is allowed to do is
**refuse to start** a layer there is no time for. It never cuts one
short: stopping a chart sync halfway is worse than any delay it could
save. The decision is taken while everything is still whole, and what
has already been raised and accepted stays.

The rehearsal prices the whole thing in advance:

```
  layer 2 the host's binaries                6 change(s)  ~15 min
  layer 4 the platform's charts              9 change(s)  ~60 min
  ...
  32 change(s) in 215 minute(s) of estimate, budget 240
```

## When a layer fails

Everything comes down, not only that layer. The layers are ordered
because they stand on one another, and leaving four raised while the
fifth comes down is a combination nobody described and nobody has ever
tested.

The window reverts its own commits newest first, pushes, lets ArgoCD
converge, and then checks the **tree** against the photo. If a commit
does not revert cleanly, or the tree does not come back, the outcome is
`needs-a-human` and **the maintenance page stays up**: putting a broken
instance back in front of the public is the one thing the page exists to
prevent.

And if the layer that failed was 1 or 9, the report says so plainly: the
tree came back, the host did not.

## What it refuses, and how to overrule it

```bash
aegis update window --yes --allow-major cert-manager   # by name, one at a time
aegis update window --yes --k3s-minor                  # read what it does first
aegis update window --yes --kernel                     # installs; never reboots
aegis update window --yes --layer 4 --layer 5          # only these, in protocol order
```

Every refusal is printed with the flag that would lift it. A proposal
that hides what it will not do is not a plan.

## What is not here yet

The monthly clock and the console page: a user timer that **only
notices** that a window is due, the metric
`aegis_update_pins_behind{class}` beside the vigía's own, and an
«Updates» page fed by `update status`.

Tenant application images are outside all of this, as they are outside
the vigía: that gap is named in `images.md` §7 and is not closed here.
