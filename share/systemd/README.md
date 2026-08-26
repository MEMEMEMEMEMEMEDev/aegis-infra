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
