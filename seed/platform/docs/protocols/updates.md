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
with the releases of the projects that publish binaries. **Six
answers**, and the last three are why this is careful:

| answer | what it means |
|---|---|
| **al día** | the pin is on the newest candidate |
| **atrasado** | there is a newer one, named |
| **desaparecido** | the pinned tag no longer exists upstream |
| **sin arriba** | there is nobody to ask: this instance builds it |
| **sin orden** | upstream answered and its tags carry no order anybody can follow |
| **no medible** | the instrument never reached the subject: a timeout, a 429, a repository that would not talk |

The first plan had four of these, with the last three under one name.
Writing the console's Updates page is what showed the cost: `inventory`
exited 2 on a perfectly healthy instance, every day, because three
images it builds itself and two tag schemes nobody can order were being
reported as «I could not look». A verdict that never changes is a
verdict nobody reads, and it is the same disease one level up.

**Sin arriba** and **sin orden** are ANSWERS. They have reasons attached
and they will read the same next month; no retry makes them better and
no window will ever act on them. **No medible** is the third outcome,
it is usually transient, and **only that one makes the command exit 2**.

A newer candidate has to carry the **same shape**: `3.22` is a series
and `3.24.2` is a point release of another one, so the second is never
offered to somebody who pinned the first. A tag with a build number and
a git hash in it — `3355.v388858a_47b_33-23` — is **sin orden**, because
sorting it is inventing an order the publisher never promised, and a
window that acts on an invented order updates to something nobody chose.

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
`MAINTENANCE_ON` it **asks the public sites**, from the machine it runs
on, and compares against the codes it took as part of its photo. If
nothing moved, the hook did not do what it says, and the window **stops
there having changed nothing** — a maintenance page nobody can see is
worse than none at all, because it is the false belief that the sites
are shielded.

It asks the sites and not the round, and that took four windows to
learn. The round measures the ORIGIN through probes that run every
thirty seconds, and its readings are keyed on the shape of a sentence
with the digits flattened — which is what makes two rounds comparable
at all, and which makes «1 of the 5 public site(s) do not answer» and
«5 of the 5» the same key with the same state. The page's whole effect
is that number, and the page lives at the edge, not at the origin.

What is demanded is only that **something changed**. aegis knows
nothing about what your page returns, and a site that sits behind its
own login answers 302 on an ordinary day. On an instance whose
contracts declare no domain there is nothing to take off the air, and
that is reported as «the effect cannot be read», never as «no effect».

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

**A chart that DROPS a resource leaves an orphan.** This platform does
not prune automatically — deleting is not something a sync should
decide on its own — so when an upgrade stops rendering something the
old version created, the object stays in the cluster and the
Application reads `OutOfSync` for ever. cert-manager 1.20.2 → 1.21.2
did exactly that on 2026-09-20, with every pod healthy on the new
version: two RBAC objects the new chart no longer writes.

The window does not delete them. It names them —kind, namespace and
name— and hands the decision over, because removing a resource is
irreversible and belongs to a person.

And it does not wait for them either. The photo records which
Applications were **already adrift** before the window started, and
every wait exempts those: the acceptance's rule is «no NEW failures»,
and asking a window to fix something it did not break —something it
CANNOT fix, when what holds the app out is an orphan the platform
declines to prune— is a rule no window can satisfy. One permanently
OutOfSync app would otherwise time out every window from then on.

**A candidate that does not render is a refusal, not a failure.** The
`helm template` pre-check runs before a line is written, so a chart
whose new version wants values this instance does not declare is named,
skipped, and the rest of the layer carries on. Undoing five charts that
rendered and settled because a sixth needs a migration somebody has to
read would be punishing the instance for the migration. vmagent 0.46 →
0.47 is exactly that: the new chart wants a `remoteWrite` block.

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

## What every acceptance is measured against

Not the photo. **A round taken with the page up and nothing else
changed yet.**

The round measures the tenant sites through their probes, and those go
out through the edge — which is exactly where the maintenance page
lives. With the page raised the sites stop answering, so comparing
against the photo reads the page doing its job as damage the window
caused. That is the plan's own distinction: the acceptance under the
page is **at the origin**, and the edge is accepted afterwards, once
the page is down.

With no page configured there is nothing to re-baseline and the photo
is the baseline.

## A sync is a request, not an arrival

Every layer that asks ArgoCD to converge then **waits for every
Application to be Synced and Healthy** before anything judges it. A
timeout counts as not settled, never as settled.

It is not a theoretical care. Layer 5 bumps images written by hand, and
`busybox` and `curl` live in the init containers of half the platform:
raising them rolls Jenkins, and a Jenkins that is restarting has «no
build at all» on every one of its fourteen jobs. A window that judged
at once called that damage and stopped. Nothing was wrong — the
instance healed in four minutes.

The rollback waits too, for the same reason: reporting that the tree
came back while the cluster is still rolling has measured nothing.

## A bump that only reached git is not a bump

A sync applies a file. The question nobody asked for a long time is
**who applies the file that was edited**.

For almost everything the answer is «the app itself»: the file is the
app's contents, and `aegis sync <app>` puts it in place. For a chart it
is not. A chart's `targetRevision` is written in the **Application
object**, under `k8s/argocd-apps`, and that directory is the source of
the App-of-Apps — which carries no `automated` policy on purpose:
nothing on this platform creates or retargets an Application without a
person.

So a chart layer that edits git, pushes, and syncs the app asks the app
to reconcile its contents against the version its object *still names*.
It does. Perfectly. Synced, Healthy, no new failures in the round,
because the instance has not changed. The layer reports itself raised.

Measured 2026-09-20: argocd 9.5.20 → 9.7.1, kyverno 3.8.1 → 3.9.1,
jenkins 5.9.29 → 5.9.63, trivy-server 0.24.0 → 0.26.0, vector
0.57.0 → 0.58.0 and vmsingle 0.45.0 → 0.46.0 were all committed,
pushed, synced, accepted, and the window closed rc 0. All six were
still running their old versions afterwards. Nothing failed anywhere:
the green was real and it was about the wrong thing.

Two rules come out of it, and check 222 holds both:

- **Whoever applies the file is synced first**, derived from the live
  Applications by asking which one's source path contains the edited
  file. Never hardcoded to a name: what an instance calls its
  App-of-Apps is the instance's business.
- **The version is read back off the live object.** «Synced+Healthy» is
  an answer about an app's contents, and the version is not in the
  contents. A layer that cannot show the version it wrote running is
  not a layer that was raised, and it fails and comes undone like any
  other.

The same shape guards the rest by construction: a file under an app's
own source routes to that app, which is what the other layers were
already doing, and a file nobody applies is a refusal rather than a
silent success.

### And the six that were already in the hole

The fix stops a window opening it. It does nothing for a chart already
there, and nothing ever would: every later reading of the tree finds
the new version written and reports the pin up to date, for ever,
because nothing else compares the two.

So the disagreement itself became something the product says. `aegis
update plan` reports each one as **wrong**, with what is written and
what is running; the metrics publish
`aegis_update_charts_unlanded{state="disagree"}` and, separately,
`{state="unreadable"}`, because a reader that lost its way to the API
must not publish a clean zero; and two alerts carry both to the phone.

**A window will not close it.** It is named as a refusal, beside the
major jumps and the k3s minors, and for a reason worth stating: a
window's way back is the photo, and the photo already found the tree
and the cluster disagreeing. There is no state to return to that the
protocol could promise. Syncing it is an ordinary operation with a
person in it — `aegis sync <the App-of-Apps>`, one at a time, watching
— or the running version goes back into the tree.

## When a layer fails

Everything comes down, not only that layer. The layers are ordered
because they stand on one another, and leaving four raised while the
fifth comes down is a combination nobody described and nobody has ever
tested.

The window reverts its own commits newest first, pushes, waits for
ArgoCD to settle, and then checks the **tree** against the photo.

If that works, the outcome is `rolled-back` and **the page comes down**.
`rolled-back` is the protocol working: the instance is byte for byte
what it was, which is exactly the state the page is not needed in.

The page stays up for one outcome only: `needs-a-human`, which means a
commit did not revert cleanly, the tree did not come back, or nobody
could measure whether it had. Putting a broken instance in front of the
public is the one thing the page exists to prevent, and that is the only
case where it might be broken.

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

## The clock, and where it is read

```bash
aegis update metrics     # the same measurement, in the exposition format
```

A user timer runs that once a day and pushes it to vmsingle
(`share/systemd/aegis-update-notice.*`). **It notices; it does not
act.** aegis never opens a window because a clock said so.

The reminder is an **alert**, not the timer, and that is a deliberate
departure from «fire on the first Sunday»: a timer that fires once a
month and misses —the machine was off, nobody was logged in— is silent
for another month, and its silence looks exactly like a month with
nothing to do. `aegis_update_window_timestamp_seconds` carries the age
of the last window, `UpdateWindowDue` reads it, and it keeps firing
until one actually closes.

| alert | what it means |
|---|---|
| `UpdatePageLeftUp` | **critical**: a window raised the maintenance page and never recorded taking it down |
| `UpdateWindowDue` | more than a month since the last window, and there is something to raise |
| `UpdateWindowNeverRun` | this instance has never opened one |
| `UpdateWindowNeedsAHuman` | **critical**: the last window could not finish, and the page may still be up |
| `UpdatePinGone` | a pinned version no longer exists upstream: this platform cannot be rebuilt from its own sources |
| `UpdateMeasurementStopped` | nobody has measured in three days, so every rule above is mute rather than green |

And the console has an **Updates** page: every pin against what upstream
says, what a window would raise in each layer, and what the last window
did commit by commit. It has no button. A window takes the sites off the
air and can roll itself back, and that does not start with a click.

## When a window is killed

Not «fails» — **killed**, the kind of death that carries no signal a
process can handle. It happened on the first day this ran for real.

Three of the four things a window changes about the machine come back
anyway: the silences carry an expiry of their own (that is what the
expiry is for), and Jenkins and the backup clock are restored by other
means. **The maintenance page has no expiry**, and on 2026-09-20 five
public sites answered 503 until a human happened to look.

So the page is the one thing that is watched from outside the process:

```bash
aegis update status     # names the window, and prints the command that undoes it
```

It reads the journal, which records every hook with its exit code, and
answers «is the page up» from that alone — never from a marker beside
it, which would be the one thing that disagrees with the record the
morning after. A hook that FAILED to take the page down counts as the
page being up, because that is exactly when it is.

`UpdatePageLeftUp` carries the same fact to the phone, because the
person who needs to know is not the one reading a terminal. Nothing
takes the page down automatically: a window that is genuinely still
running would lose its page mid-flight, which is worse than leaving it.

## What is not here yet

Tenant application images are outside all of this, as they are outside
the vigía: that gap is named in `images.md` §7 and is not closed here.

Nothing in the init installs the notice timer, which is the same gap the
backup timer had until 2026-09-16. `share/systemd/README.md` has the
five commands.
