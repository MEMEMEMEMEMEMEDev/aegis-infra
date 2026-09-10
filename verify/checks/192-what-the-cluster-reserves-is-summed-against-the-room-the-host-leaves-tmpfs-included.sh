# title: what the cluster reserves is summed against the room the host leaves, with the tmpfs counted and the two verdicts kept apart
# origin: new in v3 — measured on 2026-09-09, the day it turned out nothing in the product added memory up
check() {
# There was NO memory arithmetic anywhere in this product. `org.py`
# sums a tenant's services against that tenant's quota, and the
# ai-system quota's own comment does its sum in CPU and stops at CPU.
# So nothing ever added up what the whole platform reserves and held it
# against the machine — which is the one question whose wrong answer
# freezes somebody's desktop.
#
# Four properties are demanded of the account, and each one is a way
# the account can be wrong while still producing a number:
#
#   1 · THE TMPFS IS COUNTED. An `emptyDir` with `medium: Memory` is
#     RAM. The kernel charges it to the pod's cgroup and the scheduler
#     sees none of it. Measured 2026-09-09: 2 GiB of the house machine
#     were spoken for by two manifests and absent from every account
#     that existed. An arithmetic that drops this term is the one that
#     was already being done implicitly, and it under-reports.
#
#   2 · INIT CONTAINERS ARE A MAX, NOT A SUM. They run to completion
#     before the app containers and none is alive alongside them.
#     Summing inflates every pod that waits its turn, which — once the
#     fleet learned to take turns — is most of the AI ones. Wrong in
#     the other direction, and a budget that cries wolf gets switched
#     off.
#
#   3 · THE CEILING IS WHAT THE HOST LEAVES, not what it has. Comparing
#     against total RAM is comparing against memory the human is
#     standing on.
#
#   4 · THE TWO VERDICTS STAY APART. `requests` is a promise the
#     scheduler cannot take back: over the room left, that is a
#     failure. `limits` overcommit by design: over capacity, that is a
#     warning. Collapse them and either every healthy cluster looks
#     broken, or a real over-reservation reads as routine.
LIBH="$LIBS/aegis/host.py"
[[ -f "$LIBH" ]] || { fail "lib/aegis/host.py is not there: $LIBH"; return; }

OUT="$(python3 - "$LIBH" "$P/k8s/base/ai-system" <<'PY'
import re, sys

src = open(sys.argv[1], encoding="utf-8").read()
code = re.sub(r'"""(?:.|\n)*?"""', "", src)
code = "\n".join(l.split("#", 1)[0] for l in code.splitlines())

def body(name):
    m = re.search(r'^def %s\(.*?\):\n(.*?)(?=\n(?:def|class)\s|\Z)'
                  % re.escape(name), code, re.M | re.S)
    return m.group(1) if m else None

pod = body("_weigh_podspec")
budget = body("memory_budget")
if pod is None or budget is None:
    missing = ", ".join(n for n, b in (("_weigh_podspec", pod),
                                       ("memory_budget", budget)) if b is None)
    print("FAIL%s could not be read from lib/aegis/host.py: with no arithmetic to "
          "inspect there is nothing to measure, and that is a verdict about the "
          "reader" % missing)
    raise SystemExit

# ── 1 · the tmpfs term ───────────────────────────────────────────────
if "Memory" not in pod or "emptyDir" not in pod:
    print("FAILthe weighing does not look for `emptyDir` volumes with "
          "`medium: Memory`: that is a tmpfs, it is charged to the pod's memory "
          "cgroup, and the scheduler never sees it — 2 GiB of the house machine "
          "were invisible for exactly this reason")
if not re.search(r'tmpfs', budget):
    print("FAILthe budget does not add a tmpfs term: counting it inside the "
          "walk and dropping it from the sum is the same blind spot one step "
          "later")

# ── 2 · init containers are a max ────────────────────────────────────
init = re.search(r'initContainers(?:.|\n)*?(?=\n\s{4}\w|\Z)', pod)
if not init:
    print("FAILthe weighing ignores initContainers: a pod that waits its turn "
          "reserves what its init asks for, and after the fleet learned to take "
          "turns most of the AI pods have one")
elif "max(" not in init.group(0):
    print("FAILinitContainers are SUMMED rather than maxed: they run one after "
          "another and none is alive beside the app containers, so summing "
          "inflates every pod that waits its turn — and a budget that cries "
          "wolf gets switched off")

# ── 3 · the ceiling is what is left, not what there is ───────────────
if "allocatable_bytes" not in budget:
    print("FAILthe budget does not compare against `allocatable_bytes`: measuring "
          "against the machine's total is measuring against memory the human is "
          "standing on")

# ── 4 · the two verdicts stay apart ──────────────────────────────────
fits = re.findall(r'"(\w*_fit\w*)"\s*:', budget)
if len(set(fits)) < 2:
    print("FAILthe budget produces %d verdict(s): what the cluster RESERVES and "
          "what it may TAKE are different claims with different consequences, "
          "and collapsing them makes either every healthy cluster look broken "
          "or a real over-reservation read as routine" % len(set(fits)))
else:
    # the reserving verdict must be measured against what is LEFT, and
    # the taking one against the whole machine. Swapped, both sentences
    # still parse and both answers are wrong.
    m = re.search(r'"reserves_fit"\s*:\s*([^,\n]+)', budget)
    if m and "allocatable" not in m.group(1):
        print("FAIL`reserves_fit` is not measured against what the host leaves "
              "over: requests are what the scheduler promises, and the promise "
              "has to fit in the room that is actually free")
    m = re.search(r'"takes_fit"\s*:\s*([^,\n]+)', budget)
    if m and "ram_total" not in m.group(1):
        print("FAIL`takes_fit` is not measured against the machine's capacity: "
              "ceilings overcommit on purpose, and judging them against the "
              "leftover room turns normal into broken")

# ── 5 · the GPU lane counts only where there is one ──────────────────
# The engines carry no `replicas:` (the controller scales them from
# zero), and reading "absent" as one charged 11 GiB of engines to a
# host with no card. On a 16 GiB VPS with AI=cpu that is phase 87
# refusing a valid install. Measured 2026-09-10.
rep = body("_replicas")
if rep is None:
    print("FAILthe weighing has no _replicas: an absent replicas field has to be "
          "read as a controller-scaled pod, not as one")
elif not (re.search(r'"cpu"', rep) and re.search(r'\bai\b', rep)):
    print("FAILthe GPU engines are counted regardless of the instance's AI lane: on "
          "a host without a card they are 11 GiB that will never be asked for, and "
          "the budget refuses installs that fit")

# ── and the manifests still carry the term the account depends on ────
import pathlib
shm = 0
for p in sorted(pathlib.Path(sys.argv[2]).glob("*.yaml")):
    # comments stripped, and it is not pedantry: the quota's own
    # comment now EXPLAINS `medium: Memory`, and counting that would
    # report three manifests mounting a tmpfs where two do. Prose is
    # not code — six repetitions of that on this project's record, and
    # this check produced the seventh in its first minute.
    text = "\n".join(l.split("#", 1)[0]
                     for l in p.read_text(encoding="utf-8").splitlines())
    if re.search(r'medium:\s*Memory', text):
        shm += 1
print("    _weigh_podspec and memory_budget inspected · %d ai-system manifest(s) "
      "mount a tmpfs the scheduler cannot see" % shm)
PY
)" || { fail "the reading of the host arithmetic could not be completed"; return; }

printf '%s\n' "$OUT" | grep -v '^FAIL'
if printf '%s\n' "$OUT" | grep -q '^FAIL'; then
    fail "the memory account: $(printf '%s\n' "$OUT" | sed -n 's/^FAIL//p' | paste -sd'; ')"
else
    pass "the account counts the tmpfs, maxes the init containers, measures against the room the host leaves, and keeps reserving apart from taking"
fi
}
