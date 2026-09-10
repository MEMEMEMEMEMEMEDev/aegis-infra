# title: no engine sizes a thread pool larger than the CPU limit it runs under, and the GPU lanes still take turns
# origin: new in v3 — measured on 2026-09-09 inside the live engine-cpu: nproc 32, sixty threads, limits.cpu 6
check() {
# NOTHING INSIDE A CONTAINER KNOWS ITS OWN LIMIT. A cgroup caps CPU
# TIME; it does not change what the kernel reports, so `nproc` in a pod
# limited to 6 CPUs still answers with the machine's 32. Every library
# that sizes a pool from `cpu_count()` therefore sizes it for a machine
# it is not allowed to use, and the symptom is not an error — it is
# throttling and latency, which read as "the model is slow".
#
# Measured that day in the live pod: `nproc` 32, sixty threads in the
# process, `limits.cpu` 6. `motor.py` reads eight AEGIS_HILOS_* /
# AEGIS_OBREROS_* variables and its own comment describes the budget as
# "40 at the theoretical peak, over 32 threads" — and the manifest set
# none of the eight.
#
# A manifest cannot compute, so the values are written down. What is
# checked is the RELATIONSHIP: every declared thread cap has to answer
# to the `limits.cpu` of the container it sits in. That is the pair
# that drifts — raise the limit and the caps stay, lower it and they
# oversubscribe — and it drifts silently because both halves keep
# looking reasonable on their own.
#
# The second half is the turn the GPU lanes take. `engine-mt` waits for
# `engine-llm` to serve before reserving its own VRAM. That chain is
# load-bearing and easy to delete by accident.
AI="$P/k8s/base/ai-system"
[[ -d "$AI" ]] || { fail "the ai-system manifests are not there: $AI"; return; }

OUT="$(python3 - "$AI" <<'PY'
import pathlib, re, sys, yaml

root = pathlib.Path(sys.argv[1])

# The caps that answer to a CPU limit. Value: how many of that thing a
# single unit of the limit may be sized for. 1 means "never above the
# limit itself".
PER_CPU = {"OMP_NUM_THREADS": 1, "MKL_NUM_THREADS": 1,
           "OPENBLAS_NUM_THREADS": 1, "TORCHINDUCTOR_COMPILE_THREADS": 1}


def cpu_millis(q):
    s = str(q).strip()
    return int(s[:-1]) if s.endswith("m") else int(float(s) * 1000)


checked = 0
turns = {}
for p in sorted(root.glob("*.yaml")):
    for d in yaml.safe_load_all(p.read_text(encoding="utf-8")):
        if not isinstance(d, dict) or d.get("kind") not in (
                "Deployment", "StatefulSet", "DaemonSet"):
            continue
        name = (d.get("metadata") or {}).get("name", "?")
        spec = ((d.get("spec") or {}).get("template") or {}).get("spec") or {}
        for c in (spec.get("containers") or []):
            lim = ((c.get("resources") or {}).get("limits") or {}).get("cpu")
            env = {e.get("name"): e.get("value")
                   for e in (c.get("env") or []) if isinstance(e, dict)}
            for var, per in PER_CPU.items():
                if var not in env:
                    continue
                checked += 1
                if lim is None:
                    print("FAIL%s/%s sets %s but the container declares no "
                          "limits.cpu: a thread cap that answers to nothing is "
                          "a number somebody will read as measured"
                          % (name, c.get("name"), var))
                    continue
                try:
                    want = cpu_millis(lim) * per // 1000
                    got = int(env[var])
                except (TypeError, ValueError):
                    print("FAIL%s/%s: %s or limits.cpu is not a number this "
                          "check can compare" % (name, c.get("name"), var))
                    continue
                if got > want:
                    print("FAIL%s/%s sets %s=%d against limits.cpu %s: inside "
                          "the container nproc reports the MACHINE's threads, "
                          "so a cap above the limit is the oversubscription "
                          "this exists to stop" % (name, c.get("name"), var,
                                                   got, lim))
        # The turn one GPU lane takes before reserving its VRAM. WHO IT
        # WAITS FOR COMES FROM THE URL IT POLLS, not from the text
        # around it: the wait prints "engine-llm serves: ..." when it
        # succeeds, so a blob search finds that name even after the URL
        # has been pointed at localhost. Measured while writing this
        # check — the tooth that repoints the URL stayed green until
        # the reading moved to the URL itself. A mention is not a use.
        for ic in (spec.get("initContainers") or []):
            if ic.get("name") != "wait-for-turn":
                continue
            blob = "\n".join(str(a) for a in (ic.get("args") or []))
            urls = re.findall(r'https?://([a-z0-9.-]+)', blob)
            turns[name] = sorted({u.split(".")[0] for u in urls
                                  if u.split(".")[0].startswith("engine-")
                                  and u.split(".")[0] != name})

if not checked:
    print("FAILno engine declares a thread cap at all: with no subject, finding "
          "no oversubscription is a verdict about the reader and not about the "
          "artifact")

# engine-mt waiting on engine-llm is the chain that exists and is
# load-bearing. It is DERIVED here, not asserted by name, so that a
# fleet which grows a third lane is described rather than rejected.
if not turns:
    print("FAILno engine waits its turn: the GPU lanes reserve their KV cache "
          "once and for good, and two of them measuring free VRAM in the same "
          "instant is how a cache comes out permanently small")
for who, waits in sorted(turns.items()):
    if not waits:
        print("FAIL%s has a wait-for-turn that names no other engine: it waits "
              "for nothing, which is the same as not waiting while looking "
              "like it does" % who)

print("    %d thread cap(s) checked against their limits.cpu · %s"
      % (checked, ", ".join("%s waits for %s" % (k, "+".join(v))
                            for k, v in sorted(turns.items())) or "no turns"))
PY
)" || { fail "the reading of the ai-system manifests could not be completed"; return; }

printf '%s\n' "$OUT" | grep -v '^FAIL'
if printf '%s\n' "$OUT" | grep -q '^FAIL'; then
    fail "the engines' thread budget: $(printf '%s\n' "$OUT" | sed -n 's/^FAIL//p' | paste -sd'; ')"
else
    pass "every declared thread cap answers to the CPU limit of the container it sits in, and the GPU lanes still take turns"
fi
}
