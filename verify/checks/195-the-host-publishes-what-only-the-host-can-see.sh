# title: the host reports on itself with watermarks and counters, on a clock its readers can follow, and fails loudly
# origin: new in v3 — measured on 2026-09-09: of 1670 series in vmsingle, zero began with node_
check() {
# aegis measured its containers and never the computer they run on. Of
# 1670 series in this instance's vmsingle, ZERO began with `node_`. So
# when the operator's session froze under the AI engines, the platform
# had nothing to show: the post-mortem numbers came out of cAdvisor's
# root cgroup, which is there by accident and was never meant to be the
# record.
#
# The producer is a systemd timer on the HOST, pushing to vmsingle's
# import endpoint, because what it measures does not exist inside the
# cluster — /proc/pressure/memory, the root cgroup's slices and
# nvidia-smi are invisible to a pod. The precedent is
# aegis-backup.service. The prize is that no DaemonSet, no RBAC and no
# new scrape job come with it, so `__OBS_SCRAPE_JOBS_MIN__` does not
# move and check 092 §8 has nothing new to cross.
#
# What that shape can get wrong, and what is demanded here:
#
#   1 · A SAMPLER THAT READS GAUGES IS BLIND. Once a minute cannot see
#     a start-up spike that lasted eight seconds — unless it reads the
#     WATERMARK the spike left. `memory.peak` is monotonic and the
#     kernel keeps it; reading `memory.current` instead would produce a
#     calm graph of a machine that was not calm.
#   2 · VRAM HAS NO WATERMARK. nvidia-smi answers about this instant
#     and forgets, so the producer has to keep its own. Without it the
#     moment the desktop and both engines wanted the card at once is
#     simply not in the record — the moment that killed a session on
#     2026-09-06.
#   3 · THE CLOCK HAS TO FIT THE READERS. Every window in the rules is
#     sized in periods of this timer. A timer slower than the windows
#     empties them.
#   4 · A SILENT PUSH IS THE DISEASE. The backup unit prefixes its
#     measurement with `-` and is right to: the capture already
#     happened. Here the measurement IS the work, and a `-` would leave
#     a dashboard green because nothing ever arrived.
CMD="$LIBEXEC/aegis-host"
SVC="$AEGIS_ROOT/share/systemd/aegis-host-metrics.service"
TIM="$AEGIS_ROOT/share/systemd/aegis-host-metrics.timer"
for f in "$CMD" "$SVC" "$TIM"; do
    [[ -f "$f" ]] || { fail "the host reporter is incomplete: $f is not there"; return; }
done

OUT="$(python3 - "$CMD" "$SVC" "$TIM" "$P/k8s/base/observability/rules/vmalert-rules.yaml" <<'PY'
import re, sys, yaml

cmd = open(sys.argv[1], encoding="utf-8").read()
svc = open(sys.argv[2], encoding="utf-8").read()
tim = open(sys.argv[3], encoding="utf-8").read()

code = re.sub(r'"""(?:.|\n)*?"""', "", cmd)
code = "\n".join(l.split("#", 1)[0] for l in code.splitlines())
m = re.search(r'^def metrics\(.*?\):\n(.*?)(?=\n(?:def|class)\s|\Z)', code, re.M | re.S)
if not m:
    print("FAILaegis-host defines no metrics(): the verb the push invokes is the one "
          "check 092 follows to attribute these series, and there is nothing to read")
    raise SystemExit
body = m.group(1)

# 1 · the watermark
if "peak_bytes" not in body:
    print("FAILthe report publishes no cgroup watermark: a sampler that reads only "
          "`current` is blind to the start-up spike it exists to catch, and draws a "
          "calm graph of a machine that was not calm")

# 2 · VRAM keeps its own
if "_vram_watermark" not in body and "vram_peak" not in body:
    print("FAILVRAM is published without a watermark: nvidia-smi answers about this "
          "instant and forgets, so the moment the desktop and the engines wanted the "
          "card at once would not be in the record — which is the moment that killed a "
          "session on 2026-09-06")

# and the enforced floor is read from the kernel, not from our own file
if "/sys/fs/cgroup" not in body:
    print("FAILthe report does not read /sys/fs/cgroup: whether the floor is really "
          "held has to come from the kernel and never from the file this product wrote "
          "— a drop-in that did not take effect looks identical to one that did")

# 3 · the clock against the windows that read it
mt = re.search(r'^OnUnitActiveSec=(\d+)(s|min|m|h)\s*$', tim, re.M)
if not mt:
    print("FAILthe timer declares no OnUnitActiveSec this check can read: the cadence "
          "is what every window in the rules is sized against")
else:
    secs = int(mt.group(1)) * {"s": 1, "m": 60, "min": 60, "h": 3600}[mt.group(2)]
    rules = yaml.safe_load(open(sys.argv[4], encoding="utf-8"))["data"]
    fam = yaml.safe_load(rules.get("anfitrion.yaml", "groups: []"))
    windows = []
    for g in fam.get("groups") or []:
        for r in g.get("rules") or []:
            for n, u in re.findall(r'aegis_host_[a-z_]+\[(\d+)([smhd])\]', r.get("expr", "")):
                windows.append(int(n) * {"s": 1, "m": 60, "h": 3600, "d": 86400}[u])
    if not windows:
        print("FAILno rule reads a windowed aegis_host_* series: the family cannot be "
              "sized against the timer if nothing in it names a window")
    else:
        tightest = min(windows)
        if secs * 2 > tightest:
            print("FAILthe timer pushes every %ds and the tightest window that reads it "
                  "is [%ds]: a window under two periods empties on one late push, and "
                  "an empty rule is indistinguishable from a healthy machine"
                  % (secs, tightest))

# 4 · the push is not allowed to fail quietly
exec_line = [l for l in svc.splitlines() if l.startswith("ExecStart=")]
if not exec_line:
    print("FAILthe unit declares no ExecStart")
else:
    e = exec_line[0][len("ExecStart="):]
    if e.startswith("-"):
        print("FAILthe push is prefixed with `-`, so a failure does not fail the unit: "
              "the backup unit is right to do that because its capture already happened, "
              "but here the measurement IS the work and silence leaves a dashboard green "
              "for never having been told anything")
    if "clusterIP" not in e:
        print("FAILthe unit does not resolve vmsingle's ClusterIP: it runs on the HOST, "
              "where the cluster's DNS names do not resolve, and a "
              "*.svc.cluster.local here would fail every single time")

print("    metrics() publishes watermarks and its own VRAM mark · timer %s · the push "
      "fails loudly" % (mt.group(0).split("=")[1] if mt else "?"))
PY
)" || { fail "the reading of the host reporter could not be completed"; return; }

printf '%s\n' "$OUT" | grep -v '^FAIL'
if printf '%s\n' "$OUT" | grep -q '^FAIL'; then
    fail "the host's report: $(printf '%s\n' "$OUT" | sed -n 's/^FAIL//p' | paste -sd'; ')"
else
    pass "the host reports watermarks and counters, on a clock its readers can follow, and its push cannot fail in silence"
fi
}
