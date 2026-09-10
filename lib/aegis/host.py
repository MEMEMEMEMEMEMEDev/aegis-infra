"""What the machine has, what it has to keep, and what is left over.

`aegis host` measures; this decides what the measurement MEANS. The two
are split because they fail differently: a probe fails when a machine
will not answer, and this fails when the numbers are missing from
plans.yaml or when nobody said who else uses the computer.

The rule inherited from `vram_limit_mib` in `libexec/aegis-ai`, and the
one every function here obeys: a value that could not be derived comes
back as a refusal that NAMES what is missing, never as a default. An
unmeasured threshold is not a permissive one; it is an absent one, and
a floor derived from a RAM total nobody read looks exactly like a floor
derived from a real machine.
"""
import json
import os

import yaml

from . import paths, quantity

# The steps of the `anfitrion:` section, and the two keys every one of
# them has to carry. Both are DERIVED from plans.yaml when it is read —
# these names exist so the validation below can say which one is
# missing, not so the code can skip reading the file.
FLOOR_KEYS = ("ram", "vram")
RESERVA_KEYS = ("sistema", "desalojo")

# The keys of `anfitrion:` that are NOT steps. This is a fact about the
# section's SHAPE, not a copy of its contents: the step names
# themselves are never written down here, they are whatever is left
# after these. A list of step names in this file would be the second
# place to edit that the whole section exists to abolish.
NON_STEPS = ("reservas", "disco_minimo", "por_omision")

# What the measurement maps onto, when nobody chose. The two words are
# the QUESTION ("is this machine shared?"), not the answer: which step
# each one leads to is declared in plans.yaml under `por_omision`.
SHARED_KEY = "compartida"
DEDICATED_KEY = "dedicada"

# Where the operator's chosen step is written down, when they choose
# one. A single word in a file, the same shape `aegis data remote
# cadence --set` uses for the backup clock.
FLOOR_FILE_NAME = "host-floor"
FLOOR_ENV = "AEGIS_HOST_FLOOR"


class Unusable(Exception):
    """The numbers or the facts needed to decide are not there.

    Deliberately not org.py's `Invalid`: that one judges a CONTRACT
    somebody wrote, this one reports that the artifact or the machine
    did not supply something the arithmetic needs. Mixing them would
    tell an operator they made a mistake when the product did.
    """


def floor_file():
    return paths.aegis_home() / FLOOR_FILE_NAME


def load_plans():
    """plans.yaml, from wherever it is legible on this machine."""
    p = paths.plans_yaml()
    if not p.is_file():
        raise Unusable(
            f"plans.yaml is not readable ({p}).\n"
            f"  It is where the numbers live, including how much of this machine\n"
            f"  aegis may take. Without it nothing here can be derived, and\n"
            f"  guessing a floor would be worse than having none.")
    try:
        return yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as e:
        raise Unusable(f"plans.yaml could not be parsed ({p}): {e}")


def check_anfitrion(plans):
    """plans.yaml carries the whole `anfitrion:` section this code indexes.

    A SEPARATE PASS over the section, in the shape of `org.py`'s
    `_check_plans` and for the same measured reason: a lookup as each
    value is needed turns a missing step into a `KeyError` deep inside
    whoever asked, and a python traceback is not a verdict — it names
    neither the file nor what is missing from it.

    It lands on a real adoption path. `plans.yaml` travels in the seed
    and an instance older than this section adopts it by COPYING the
    section across; a copy that brings only the step that instance
    happens to use is exactly the partial copy this refuses.

    Returns the section.
    """
    a = plans.get("anfitrion")
    if not a:
        raise Unusable(
            "plans.yaml carries no `anfitrion:` section.\n"
            "  It is the ceiling over every other ceiling: what aegis leaves\n"
            "  alone on the machine it landed on. The seed ships it; an\n"
            "  instance older than the field adopts it by copying it across.")

    steps = [k for k, v in a.items()
             if k not in NON_STEPS and isinstance(v, dict)]
    if not steps:
        raise Unusable(
            "plans.yaml: `anfitrion:` declares no step.\n"
            "  Without at least one, there is no floor to leave the machine and\n"
            "  no number to derive a reservation from.")
    for name in sorted(steps):
        absent = [k for k in FLOOR_KEYS if k not in (a[name] or {})]
        if absent:
            raise Unusable(
                f"plans.yaml: the anfitrion step {name!r} does not declare "
                f"{', '.join(absent)}.\n"
                f"  A step that says what to leave in RAM and not in VRAM (or the\n"
                f"  other way round) is half a floor: whichever half is missing\n"
                f"  gets derived as nothing, which is the state that froze a\n"
                f"  session on 2026-09-09.")

    reservas = a.get("reservas") or {}
    absent = [k for k in RESERVA_KEYS if k not in reservas]
    if absent:
        raise Unusable(
            f"plans.yaml: `anfitrion.reservas` does not declare "
            f"{', '.join(absent)}.\n"
            f"  They are what the host's own daemons and the kubelet's eviction\n"
            f"  margin need, and they are added to the floor to make the node's\n"
            f"  reservation. Missing, the reservation comes out too small and\n"
            f"  the scheduler goes on believing it owns the machine.")

    if not a.get("disco_minimo"):
        raise Unusable(
            "plans.yaml: `anfitrion.disco_minimo` is not declared.\n"
            "  It is the single home of the free-disk requirement, which used to\n"
            "  be written in two places with two different numbers.")

    por = a.get("por_omision") or {}
    absent = [k for k in (SHARED_KEY, DEDICATED_KEY) if k not in por]
    if absent:
        raise Unusable(
            f"plans.yaml: `anfitrion.por_omision` does not say which step a "
            f"{' or '.join(absent)} machine derives.\n"
            f"  Without it a fresh install has a measurement and no way to turn\n"
            f"  it into a floor, and the mapping would have to be guessed in\n"
            f"  code — which is the second place to edit this section exists to\n"
            f"  abolish.")
    for kind, step in por.items():
        if step not in steps:
            raise Unusable(
                f"plans.yaml: `anfitrion.por_omision.{kind}` names the step "
                f"{step!r}, which is not declared.\n"
                f"  Declared: {', '.join(sorted(steps))}.")
    return a


# Where the kernel is told to hold the floor. A systemd drop-in on
# `user.slice`, which is a REAL slice — unlike `kubepods.slice`, which
# the kubelet creates as a transient unit stamped "Do not edit" and
# regenerates on every start. Fighting that one with a drop-in would
# make aegis the second author of a file somebody else owns, which is
# the class of drift `bootstrap-host.yml` already refuses for
# containerd's config.
FLOOR_DROPIN = "/etc/systemd/system/user.slice.d/10-aegis-desktop-floor.conf"

# The live answer, and it is deliberately NOT the file above. A
# drop-in that did not take effect looks identical to one that did if
# you only read your own writing.
FLOOR_LIVE = "/sys/fs/cgroup/user.slice/memory.min"


def floor_dropin_text(f, facts):
    """The unit fragment, with its provenance in the first three lines.

    Somebody finding this file on a machine months from now should be
    able to tell what measured it and which step produced it, without
    running anything.
    """
    return (
        "# Written by `aegis host floor --apply`. Do not edit by hand:\n"
        "# `--apply` overwrites it and `--off` removes it.\n"
        f"#   step        {f['step']}  ({f['source']})\n"
        f"#   measured    {facts.get('measured_at', 'unknown')}\n"
        "#\n"
        "# A FLOOR, NOT A CAP. memory.min is irreclaimable: under memory\n"
        "# pressure the kernel reclaims from kubepods.slice before it\n"
        "# touches this. Above the floor the desktop competes like\n"
        "# anything else and may well be paged out — what this buys is\n"
        "# that it never freezes, not that it is always comfortable.\n"
        "[Slice]\n"
        "MemoryAccounting=yes\n"
        f"MemoryMin={f['ram_bytes']}\n")


# The kubelet's own merge directory. NOT `config.yaml`, and the
# distinction is the whole reason this lands cleanly: that file already
# has an owner — the task that pins `resolv-conf`, guarded by three
# literal greps in check 024 — and editing it would mean either
# rewriting somebody else's task or hanging this one off a condition
# that has nothing to do with it (on a host without systemd-resolved,
# `config.yaml` is not written at all). A drop-in is a separate file,
# written unconditionally, merged by k3s on every boot, and removed by
# deleting it.
KUBELET_DROPIN = "/etc/rancher/k3s/config.yaml.d/10-aegis-node-reserved.yaml"


def kubelet_dropin_text(r):
    """The k3s fragment, with the arithmetic that produced it above it."""
    f = r["floor"]
    # A LIST OF LINES, not a chain of concatenations. The first draft
    # mixed adjacent string literals with `+` and a `.ljust()`, and
    # python concatenated the literals FIRST -- so the padding applied
    # to the whole block and did nothing, while looking exactly like
    # alignment. Lines that are built one at a time cannot do that.
    def row(label, value, note=""):
        return "#   %-18s%s%s" % (label, value, note)

    daemons = r["system_reserved_bytes"] - f["ram_bytes"]
    lines = [
        "# Written by aegis (host bootstrap) from what the machine measured.",
        "# Do not edit by hand: it is derived, and the derivation moves it.",
        "#",
        row("machine", "%d bytes" % r["ram_total_bytes"]),
        row("floor (%s)" % f["step"], "%d bytes" % f["ram_bytes"],
            "  (%s)" % f["source"]),
        row("+ host daemons", "%d bytes" % daemons),
        row("= system-reserved", "%d bytes" % r["system_reserved_bytes"]),
        row("- eviction", "%d bytes" % r["eviction_bytes"]),
        row("= allocatable", "%d bytes" % r["allocatable_bytes"]),
        "#",
        "# `enforce-node-allocatable=pods` is the default and is written",
        "# anyway, because it is what makes the kubelet put the SAME",
        "# subtraction into kubepods.slice's memory.max. Without it this",
        "# file would move the scheduler's opinion and not the kernel's.",
        "kubelet-arg:",
        '  - "system-reserved=memory=%s"' % r["system_reserved"],
        '  - "eviction-hard=memory.available<%s"' % r["eviction"],
        '  - "enforce-node-allocatable=pods"',
    ]
    return "\n".join(lines) + "\n"


def requirements(anfitrion):
    """What a machine has to have before aegis will install on it.

    ONE home for numbers that had two. `aegis preflight` demanded 25
    GiB of free disk and the init's own gate `disco-20G` demanded 20,
    for the same registry+jenkins+trivy PVCs. Two thresholds for one
    requirement means one of them is wrong and nobody can say which —
    and the README, which publishes 25, could not be checked against
    either of them because neither was readable from anywhere else.
    """
    return {
        "disk_free_bytes": quantity.mem(anfitrion["disco_minimo"]),
        "disk_free": str(anfitrion["disco_minimo"]),
    }


def steps_of(anfitrion):
    """The step names, DERIVED from the section and never listed here."""
    return sorted(k for k, v in anfitrion.items()
                  if k not in NON_STEPS and isinstance(v, dict))


def read_facts():
    """The host profile `aegis host measure` wrote, or a refusal."""
    p = paths.aegis_home() / "host.json"
    if not p.is_file():
        raise Unusable(
            f"this machine has not been measured ({p} is not there).\n"
            f"  Run `aegis host measure` first. Nothing here invents a machine.")
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise Unusable(
            f"the host profile could not be read ({p}): {e}\n"
            f"  It is not that the machine is fine: it is that the measurement\n"
            f"  is unreadable. Re-run `aegis host measure`.")


def chosen_step(anfitrion, facts):
    """Which step applies, and WHERE that came from.

    Three sources, in this order, and the order is the point: what the
    operator says for one run beats what they wrote down, and both beat
    what the machine implies. Every answer carries its provenance so
    `aegis host show` can print not just the number but why it is that
    number.

      1. $AEGIS_HOST_FLOOR             — this run only
      2. $AEGIS_HOME/host-floor        — written by `aegis host floor --set`
      3. derived from the measurement  — the default, and the common case

    The derivation itself is one line: a machine somebody shares gets
    `compartido`, a machine nobody shares gets `dedicado`. It is
    deliberately the timid choice of the two, because the derivation
    runs on machines whose owner has not measured anything yet.

    If the measurement could not tell whether a human is there, this
    REFUSES. Not knowing is not the same as knowing there is nobody,
    and the difference is a frozen session.
    """
    known = steps_of(anfitrion)

    env = os.environ.get(FLOOR_ENV)
    if env:
        return _validated(env.strip(), known, f"${FLOOR_ENV}")

    f = floor_file()
    if f.is_file():
        word = f.read_text(encoding="utf-8").strip()
        if word:
            return _validated(word, known, str(f))

    shared = facts.get("shared_with_a_human")
    if shared is None:
        raise Unusable(
            "whether a human shares this machine could not be established, so "
            "no floor can be derived.\n"
            "  Not knowing is not the same as knowing there is nobody: the one\n"
            "  time the difference matters is the moment somebody sits down.\n"
            f"  Choose deliberately:  aegis host floor --set <{'|'.join(known)}>")
    # The mapping is READ, not written here: plans.yaml says which step
    # a shared machine derives and which one a dedicated machine does.
    # `check_anfitrion` has already refused a file that does not say.
    kind = SHARED_KEY if shared else DEDICATED_KEY
    step = anfitrion["por_omision"][kind]
    return step, ("measured: a human shares this machine" if shared
                  else "measured: no graphical session")


def _validated(word, known, where):
    if word not in known:
        raise Unusable(
            f"{where} asks for the anfitrion step {word!r}, which plans.yaml "
            f"does not declare.\n"
            f"  Declared: {', '.join(known)}.")
    return word, where


def floor(anfitrion, facts):
    """The floor in bytes and MiB, with the step and its provenance."""
    step, source = chosen_step(anfitrion, facts)
    s = anfitrion[step]
    return {
        "step": step,
        "source": source,
        "ram_bytes": quantity.mem(s["ram"]),
        "vram_mib": int(quantity.mem(s["vram"]) / (1024 ** 2))
        if str(s["vram"]).strip() not in ("0", "") else 0,
    }


# ── what the cluster asks of the machine ─────────────────────────────
#
# There was no memory arithmetic ANYWHERE in this product before
# 2026-09-09. `org.py` sums a tenant's services against its quota, and
# the ai-system quota's own comment does the sum in CPU and stops. So
# nothing ever added up what the whole platform reserves and held it
# against the machine — the one question whose wrong answer freezes a
# desktop.
#
# Two numbers come out, and keeping them apart is the point:
#
#   RESERVES  requests + the tmpfs nobody counts. This is what the
#             scheduler PROMISES and cannot take back. Over the room
#             the host leaves, it is a FAILURE.
#   TAKES     limits + the same tmpfs. Ceilings overcommit on purpose
#             and always have. Over the machine's capacity it is a
#             WARNING, and treating it like the first number would make
#             every healthy cluster look broken.

_POD_KINDS = ("Deployment", "StatefulSet", "DaemonSet", "ReplicaSet",
              "Job", "Pod", "ReplicationController")


def _res_bytes(res, side):
    try:
        return quantity.mem((res or {}).get(side, {}).get("memory"))
    except (AttributeError, TypeError, ValueError):
        return 0


def _weigh_podspec(spec):
    """(requests, limits, tmpfs) of one pod, the way the kubelet counts.

    INIT CONTAINERS ARE A MAX, NOT A SUM, and that is not a detail: they
    run to completion one after another and none of them is alive when
    the app containers are. Summing them would inflate every pod that
    waits for its turn — which, after the fleet learned to take turns,
    is most of the AI ones.

    The tmpfs is the term nobody had. An `emptyDir` with
    `medium: Memory` is RAM: the kernel charges every byte written to
    it against the pod's memory cgroup, and the scheduler does not see
    it in `requests` at all. Measured 2026-09-09: the two GPU engines
    carry 1Gi of /dev/shm each, so 2 GiB of this machine were spoken
    for by manifests and invisible to every account that existed.
    """
    req = lim = 0
    for c in spec.get("containers") or []:
        req += _res_bytes(c.get("resources"), "requests")
        lim += _res_bytes(c.get("resources"), "limits")
    ireq = ilim = 0
    for c in spec.get("initContainers") or []:
        ireq = max(ireq, _res_bytes(c.get("resources"), "requests"))
        ilim = max(ilim, _res_bytes(c.get("resources"), "limits"))
    tmpfs = 0
    for v in spec.get("volumes") or []:
        ed = (v or {}).get("emptyDir")
        if isinstance(ed, dict) and ed.get("medium") == "Memory" and ed.get("sizeLimit"):
            tmpfs += quantity.mem(ed["sizeLimit"])
    return max(req, ireq), max(lim, ilim), tmpfs


def _walk_bare_resources(node, out, seen_ids):
    """`resources:` blocks that are not inside a pod spec.

    The seed declares resources in TWO shapes and both are real: raw
    manifests, and the `values.yaml` of the charts it pins. A walk that
    only understood manifests would miss observability and jenkins
    entirely and report a reassuring number.
    """
    if id(node) in seen_ids:
        return
    seen_ids.add(id(node))
    if isinstance(node, dict):
        r = node.get("resources")
        if isinstance(r, dict) and ("requests" in r or "limits" in r):
            out["requests"] += _res_bytes(r, "requests")
            out["limits"] += _res_bytes(r, "limits")
        for k, v in node.items():
            if k == "resources":
                continue
            _walk_bare_resources(v, out, seen_ids)
    elif isinstance(node, list):
        for v in node:
            _walk_bare_resources(v, out, seen_ids)


def _wants_gpu(pod):
    """A pod is a GPU-lane pod if any container asks the device plugin for a card."""
    for c in (pod.get("containers") or []):
        lim = (c.get("resources") or {}).get("limits") or {}
        if any(str(k).startswith("nvidia.com/") for k in lim):
            return True
    return False


def _replicas(kind, spec, pod, ai):
    """How many of this pod the budget should count.

    Declared replicas win. A Deployment that declares NONE is one a
    controller scales, and in this seed those are exactly the GPU
    engines: asleep at birth, raised to one by `aegis ai open`. They
    count as one only on an instance whose lane is `gpu` -- the
    reservation is what an open working day would demand -- and as
    zero on a lane that will never wake them. Unknown lane: counted,
    said out loud by the caller, never silently the cheaper number.
    """
    if kind in ("DaemonSet", "Pod"):
        return 1
    if "replicas" in spec:
        return int(spec["replicas"] or 0)
    if _wants_gpu(pod):
        return 0 if ai in ("cpu", "no") else 1
    return 1


def weigh_seed(base_dir, ai=None):
    """What the artifact declares it will ask of a machine.

    Read from the seed and not from a cluster, because the question it
    answers is the one a stranger asks BEFORE installing: will this
    machine hold what aegis is about to deploy? That question had no
    answer, and the freeze it should have predicted is the reason this
    exists.

    WHAT IT CANNOT SEE, said out loud rather than rounded away: a
    chart's OWN defaults for anything the seed does not override. The
    seed pins versions and overrides the resources it cares about; what
    it leaves alone is decided inside a tarball this walk never opens.
    So the number is a FLOOR of what will be asked, never a ceiling,
    and every caller prints it as such.

    THE GPU LANE IS COUNTED ONLY WHEN THIS INSTANCE HAS ONE. The GPU
    engines carry no `replicas:` in the seed -- they are born at zero
    and the mode controller scales them -- and the first version of
    this walk read "absent" as one. Measured 2026-09-10: 11 GiB of
    engines counted on a host that would never run them, which on a
    16 GiB VPS with AI=cpu would have made phase 87 refuse a perfectly
    valid install. `ai` is the instance's lane (`AI` in aegis.conf);
    when it is unknown the engines ARE counted, because guessing the
    cheaper answer is how a budget stops meaning anything.
    """
    import pathlib
    base = pathlib.Path(base_dir)
    total = {"requests": 0, "limits": 0, "tmpfs": 0}
    files = 0
    if not base.is_dir():
        raise Unusable(
            f"the seed's manifests are not readable ({base}).\n"
            f"  Without them there is nothing to weigh, and reporting a small\n"
            f"  number would be worse than reporting none.")
    for p in sorted(base.rglob("*.yaml")):
        try:
            docs = list(yaml.safe_load_all(p.read_text(encoding="utf-8")))
        except (OSError, yaml.YAMLError):
            continue
        files += 1
        for d in docs:
            if not isinstance(d, dict):
                continue
            kind = d.get("kind")
            if kind in _POD_KINDS:
                spec = d.get("spec") or {}
                pod = (spec.get("template") or {}).get("spec") or (
                    spec if kind == "Pod" else {})
                if not pod:
                    continue
                n = _replicas(kind, spec, pod, ai)
                r, l, t = _weigh_podspec(pod)
                total["requests"] += r * n
                total["limits"] += l * n
                total["tmpfs"] += t * n
            else:
                # a chart's values, or anything else that declares
                # resources without a pod around them
                bare = {"requests": 0, "limits": 0}
                _walk_bare_resources(d, bare, set())
                total["requests"] += bare["requests"]
                total["limits"] += bare["limits"]
    total["files"] = files
    return total


def memory_budget(anfitrion, facts, base_dir):
    """The account: what the cluster asks, against what the host leaves.

    Written in the shape of `org.py`'s `_check_quota_arithmetic` — the
    terms, the sum, the ceiling, and the ways out named — because an
    account the operator cannot follow is a number they have to trust,
    and this one is telling them their computer is about to freeze.
    """
    r = node_reservation(anfitrion, facts)
    ai = (paths.read_conf().get("AI") or "").strip() or None
    w = weigh_seed(base_dir, ai)
    w["ai_lane"] = ai or "unknown (GPU engines counted)"
    reserves = w["requests"] + w["tmpfs"]
    takes = w["limits"] + w["tmpfs"]
    return {
        "reservation": r,
        "seed": w,
        "reserves_bytes": reserves,
        "takes_bytes": takes,
        # RESERVES over what is left is a failure: the scheduler cannot
        # unpromise it.
        "reserves_fit": reserves <= r["allocatable_bytes"],
        # TAKES over capacity is a warning: ceilings overcommit by
        # design, and calling that broken would make every healthy
        # cluster look sick.
        "takes_fit": takes <= r["ram_total_bytes"],
    }


def node_reservation(anfitrion, facts):
    """What the kubelet has to be told to keep away from pods.

    ONE number decides two things that used to be able to disagree, and
    that is why it is derived here rather than written anywhere:

      · `system-reserved` lowers the node's `allocatable`, so the
        SCHEDULER stops promising memory that is not there;
      · with `enforce-node-allocatable=pods` the kubelet writes
        `kubepods.slice`'s own `memory.max` from the same subtraction,
        so the KERNEL stops letting the cluster reach for the whole
        machine.

    Measured 2026-09-09: `allocatable == capacity` and
    `kubepods.slice/memory.max` was 32448565248 — exactly the machine.
    The enforcement mechanism was already there; what was missing was
    anything reserved.
    """
    f = floor(anfitrion, facts)
    ram = facts.get("ram_total_bytes")
    if ram is None:
        raise Unusable(
            "the machine's total RAM was not measured, so no reservation can "
            "be derived from it.\n"
            "  `undetermined` in host.json says so; re-run `aegis host measure`\n"
            "  on a machine where /proc/meminfo is readable.")
    reservas = anfitrion["reservas"]
    sistema = quantity.mem(reservas["sistema"])
    desalojo = quantity.mem(reservas["desalojo"])
    # system-reserved covers everything outside kubepods: the person AND
    # the host's own daemons. They are added and not maxed, because they
    # are different memory held at the same time.
    system_reserved = f["ram_bytes"] + sistema
    allocatable = ram - system_reserved - desalojo
    return {
        "floor": f,
        "ram_total_bytes": ram,
        "system_reserved_bytes": system_reserved,
        "eviction_bytes": desalojo,
        "allocatable_bytes": allocatable,
        "system_reserved": quantity.mem_str(system_reserved),
        "eviction": quantity.mem_str(desalojo),
    }
