# The host bridge — how the platform is reached with `EDGE=local`

With `EDGE=cloudflare` nothing here is installed: the tunnel dials out
from a pod and traffic arrives at traefik's ClusterIP from inside the
cluster. With `EDGE=local` there is no tunnel and no zone, so somebody
on the HOST has to hand ports 80 and 443 to traefik.

These four units are that somebody. `systemd-socket-proxyd` listens on
the address the operator chose and forwards, byte for byte, to the fixed
ClusterIP of traefik (`10.43.0.80`, pinned in the traefik values for
exactly this reason).

## Why a bridge and not `hostPort`

Decided in `plan/98-preguntas.md` P-19, and measured against traefik's
chart 40.3.0: setting `hostPort` with a `hostIP` makes the chart render
a container port bound to that address, and traefik ends up **deaf** —
it answers on the pod's own address and nothing on the host reaches it.
The bridge sidesteps the chart entirely: traefik stays a plain
ClusterIP Service, identical in both profiles, and the host-side
plumbing lives on the host where it can be read, restarted and removed
without touching the cluster.

## Why socket activation

The socket unit holds the listening port; the proxy process is started
on the first connection and can die without losing the port. A
`destroy` that takes the cluster away leaves the bridge listening and
answering "connection refused" from traefik — which is the honest
answer — instead of leaving the port free for something else to claim.

## What the phase does with these

Phase 25 installs them under `EDGE=local`:

1. copies the four files to `/etc/systemd/system/`;
2. writes `/etc/aegis/edge.env` with `AEGIS_EDGE_UPSTREAM=<traefik ClusterIP>`;
3. if `EDGE_BIND_IP` is not the default `127.0.0.1`, drops a
   `ListenStream=` override in `aegis-edge-{http,https}.socket.d/`;
4. enables and starts the two sockets.

The shipped files are complete and valid as they are, for the default
case. There is no placeholder in this directory ON PURPOSE: check 003
sweeps `seed/` and does not look here, so a `__TOKEN__` living in this
folder would be one nobody is watching.

## aegis-host-metrics.service / .timer

What only the host can see, pushed to vmsingle once a minute.

Until 2026-09-09 this instance measured its containers and never the
computer they ran on: of 1670 series in vmsingle, zero began with
`node_`. So when the operator's graphical session froze under the AI
engines, the platform had nothing to show for it — the numbers in the
post-mortem had to be reconstructed from cAdvisor's root cgroup, which
is there by accident and was never meant to be the record.

It pushes rather than being scraped for the same reason the backup
measurement does: `/proc/pressure/memory`, the root cgroup's slices and
`nvidia-smi` do not exist inside a pod, so there is nothing for vmagent
to pull. The alternative shape is a node_exporter DaemonSet, with new
RBAC, a hostPath mount, a new scrape job and the check that
cross-checks the job count. This costs one timer.

Like the backup unit it is a USER unit, and it carries the same warning
for the same reason: **a user timer only runs while the user has a
session** unless lingering is on.

    loginctl enable-linger $USER
    systemctl --user enable --now aegis-host-metrics.timer

Unlike the backup unit, its push carries **no leading `-`**. There the
dash is right — the capture already happened and is already off-site,
so losing the measurement is not losing the backup. Here the
measurement is the whole job, and a failure that does not fail would
leave a dashboard green for never having been told anything.

The cadence is 60 s and the reason it is enough is not that a minute is
fast: the peaks are cgroup watermarks (monotonic, so a sampler reads
the mark a spike left rather than having to catch it), the stalls are
counters, and the only true gauge — VRAM — gets its own watermark kept
in `$AEGIS_HOME/host-metrics.state`. What 60 s costs is the shape of
the instantaneous curve.

Read what it publishes without waiting for the timer:

    aegis host metrics

## aegis-backup.service / .timer

The backup clock, and it is a USER unit: the capture needs the
operator's age key, their kubeconfig and a `kubectl exec` into every
tenant, and none of that belongs to root. No phase installs it. An
instance that never ran these lines has no clock, and its copies are
the ones somebody remembers to make. Measured on the house machine on
2026-09-16: the units had never been installed, and the copies were
three days old.

```bash
mkdir -p ~/.config/aegis ~/.config/systemd/user
printf 'AEGIS_HOME=%s/aegis\nAEGIS_ROOT=%s/aegis-infra\nPATH=/usr/local/bin:/usr/bin:/bin\nSOPS_AGE_KEY_FILE=%s/.config/sops/age/aegis.key\n' \
    "$HOME" "$HOME" "$HOME" > ~/.config/aegis/backup.env
cp "$(dirname "$(readlink -f "$(command -v aegis)")")"/../share/systemd/aegis-backup.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now aegis-backup.timer
loginctl enable-linger "$USER"                 # or the clock stops when you log out
systemctl --user start aegis-backup.service    # one run now, to see it work
```

`backup.env` is what the unit reads instead of your shell: systemd
starts it with no profile, so `SOPS_AGE_KEY_FILE` in particular has to
be there. Without it the bundle is written and the credential of the
destination does not decrypt, and the run fails after the capture.
`aegis data remote status` says how old each copy is, and the console's
Storage screen reads the same document.

## aegis-update-notice.service / .timer

What of everything this platform pins is behind, measured once a day on
the host and pushed to vmsingle.

**It notices. It does not act.** That is the operator's decision and it
is the whole contract of the unit: aegis never opens an update window on
its own. A window changes the platform, takes the public sites off the
air behind the operator's maintenance page, and can roll itself back —
none of that happens because a clock said so. What runs here is `aegis
update metrics`, which reads the platform checkout, asks public
registries and prints numbers. It writes nothing, commits nothing and
touches no cluster object.

It pushes rather than being scraped, for the same reason the other two
host units do: the subject lives outside the cluster. Deriving the pins
means reading the instance's platform checkout and asking registries
from the host, and no pod does either.

### Why the reminder is an alert and not this timer

The plan this came from said «a user timer that only notices that a
window is due, on the first Sunday». It is a daily measurement and an
alert instead, and the reason is the one this whole product keeps
running into: **a timer that fires once a month and misses is silent for
another month, and its silence looks exactly like a month with nothing
to do.** The machine was off, or nobody was logged in, and nothing says
so.

`aegis_update_window_timestamp_seconds` carries the age of the last
window, and `UpdateWindowDue` reads it. An age is true whenever anybody
looks at it, it keeps firing until a window actually closes, and the
same series feeds the console's Updates page.

### What it publishes

| series | what it says |
|---|---|
| `aegis_update_pins_total{class}` | versions pinned, by class |
| `aegis_update_pins_behind{class}` | a newer candidate exists, and a window would take it |
| `aegis_update_pins_current{class}` | measured and already newest |
| `aegis_update_pins_gone{class}` | the pinned tag no longer exists upstream |
| `aegis_update_pins_unactionable{class}` | built here, or tagged with no order anybody follows |
| `aegis_update_pins_unmeasurable{class}` | **nobody could ask** — the only blind one |
| `aegis_update_window_ever` | 1 once this instance has closed a window |
| `aegis_update_window_timestamp_seconds` | when the last one closed |
| `aegis_update_window_outcome{outcome}` | how it ended, one series per outcome |
| `aegis_update_measured_timestamp_seconds` | when these numbers were taken |

The last one is not decoration: a gauge nobody writes any more keeps its
last value for ever, so «0 behind» would stay green while nothing was
being measured. `UpdateMeasurementStopped` watches it.

The difference between `unactionable` and `unmeasurable` is the reason
this family exists at all. An image aegis builds itself has no upstream
to ask, and a tag like `3355.v388858a_47b_33-23` carries no order
anybody can follow. Those are **answers**, and they will read the same
next month. Only `unmeasurable` means the instrument did not reach the
subject.

### Installing it

Nothing in the init installs these units — the same gap the backup timer
had, found on 2026-09-16. Until a phase does:

```bash
mkdir -p ~/.config/systemd/user
cp /usr/local/share/aegis/systemd/aegis-update-notice.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now aegis-update-notice.timer
loginctl enable-linger $USER      # or it only runs while you are logged in
```

The first run measures fifty-odd registries with a cold cache and takes
about half a minute. After that it is seconds, and the console's Updates
page leans on the same six-hour cache.
