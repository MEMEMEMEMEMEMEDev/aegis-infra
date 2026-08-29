# Template `worker-go` — a process that works and does not listen

Everything the `base` template is, minus the port and the public route.
It stands up in one run and, from that second on, the template is gone
from your life: what it wrote is yours (§0.3).

## What you change

- **`main.go`, the `work` function** — one pass. Keep it taking the
  context: that is what cancels whatever it calls when the pod is asked
  to stop.
- **`const every`** — the pause between passes.
- **The contract's `usa:`** — a worker usually needs something, and that
  is the whole reason it exists. Whatever is not named there, the
  NetworkPolicy blocks.
- **The memory limit** — size it for the heaviest pass. The limit is
  where the pod dies, not an average.

## What you do not change, and why

- **No port, no Service, no probe** — the contract REJECTS `puerto` and
  `publico` for this type, so a worker cannot be quietly exposed. What
  tells you it is alive is its log. If it has to answer requests, the
  type is `http` and the template is another one.
- **The SIGTERM handling** — a process that ignores it is killed 30
  seconds later by the kubelet, every rollout costs that per pod, and a
  pass interrupted mid-flight leaves exactly the half-written state the
  graceful path exists to avoid.
- **No rollout surge** — surging would run two copies of the pass at
  once. That is a question about your idempotence, not about routing,
  so the default (one at a time) is the conservative answer.
- **The two `FROM` lines** — resolved against the internal registry at
  instantiation and pinned by digest.
- **The digest marker in `k8s/overlays/dev/`** — the pipeline writes the
  real one on every build.
