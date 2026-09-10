# title: no panel calls the root cgroup the machine, and the host family's absence guard names every one of its subjects
# origin: new in v3 — measured on 2026-09-09: the panels named «Machine memory» and «Free memory» measured neither
check() {
# THE PANELS WERE CALLED «Machine memory» AND «Free memory» AND THEY
# MEASURED NEITHER. Both read
# `container_memory_working_set_bytes{id="/"}` against
# `machine_memory_bytes` — that is cAdvisor's ROOT CGROUP, which is a
# good approximation of a machine right up until the moment it matters.
# It leaves out swap, slab and the page cache; so on the day the
# operator's session was being paged out to make room for the AI
# engines, the panel that was supposed to show it stayed calm.
#
# The correction is not «use a better query». It is that the machine
# has to be measured on the machine: those two panels now read what
# `aegis host metrics` pushes from the host, and this check keeps them
# from drifting back to the convenient approximation that lives inside
# the cluster.
#
# THE SECOND HALF is the family's absence guard, and it is the rule
# check 092 states in general applied where it bites hardest. Every
# rule in the `anfitrion` family compares against a value, so every one
# of them goes EMPTY — not false — if the host stops reporting. An
# empty rule is indistinguishable from a healthy machine. The guard is
# what turns that silence into a page, and it has to name EVERY series
# the family reads: one probe can die while the rest keep pushing, and
# a guard that watches only the timestamp would sleep through it.
DASH="$P/k8s/base/observability/dashboards"
RULES="$P/k8s/base/observability/rules/vmalert-rules.yaml"
[[ -d "$DASH" ]] || { fail "the dashboards are not there: $DASH"; return; }
[[ -f "$RULES" ]] || { fail "the rules are not there: $RULES"; return; }

OUT="$(python3 - "$DASH" "$RULES" <<'PY'
import json, pathlib, re, sys, yaml

# ── 1 · no panel calls the root cgroup the machine ───────────────────
#
# MEMORY ONLY, and the narrowing is the point rather than an exemption.
# For CPU and for disk the root cgroup really is the machine: every
# process lives in some cgroup and the root aggregates them, so
# `container_cpu_usage_seconds_total{id="/"}` over `machine_cpu_cores`
# is an honest reading and «Machine CPU» is an honest title.
#
# Memory is the one that diverges, because memory is the one with
# things that belong to the machine and to no cgroup: swap, slab, and
# the page cache. That is exactly the gap the freeze fell through — the
# desktop's pages went to swap, the root cgroup's working set did not
# move, and the panel stayed calm.
ROOT = re.compile(r'container_memory_\w+\{id=\\?"/\\?"\}')
panels = 0
for p in sorted(pathlib.Path(sys.argv[1]).glob("*.yaml")):
    doc = yaml.safe_load(p.read_text(encoding="utf-8"))
    for key, blob in (doc.get("data") or {}).items():
        try:
            dash = json.loads(blob)
        except ValueError:
            print("FAIL%s/%s is not readable JSON: a dashboard nobody can parse is a "
                  "dashboard nobody can check" % (p.name, key))
            continue
        for panel in dash.get("panels") or []:
            panels += 1
            title = str(panel.get("title", ""))
            for t in panel.get("targets") or []:
                expr = t.get("expr", "")
                if not ROOT.search(expr):
                    continue
                # The root cgroup is a legitimate subject when the panel
                # SAYS that is what it is. What is forbidden is calling
                # it the machine.
                if re.search(r'\b(machine|host|memoria de la m|free memory)\b',
                             title, re.I):
                    print("FAILthe panel %r reads cAdvisor's root cgroup and calls "
                          "itself the machine: that measure leaves out swap, slab and "
                          "the page cache, which is why it stayed calm through a "
                          "session being paged out" % title)

if not panels:
    print("FAILno panel was read at all: with no subject, finding no bad query is a "
          "verdict about the reader")

# ── 2 · the family's guard names every subject it reads ──────────────
rules = yaml.safe_load(open(sys.argv[2], encoding="utf-8"))["data"]
if "anfitrion.yaml" not in rules:
    print("FAILthere is no `anfitrion` rule family: the machine publishes series and "
          "nothing alerts on them, which is paying for a measurement nobody reads")
else:
    fam = yaml.safe_load(rules["anfitrion.yaml"])
    read, guards = set(), set()
    for g in fam.get("groups") or []:
        for r in g.get("rules") or []:
            expr = r.get("expr", "")
            names = set(re.findall(r'\b(aegis_host_[a-z_]+)\b', expr))
            if "absent(" in expr:
                guards |= set(re.findall(r'absent\([^)]*?\b(aegis_host_[a-z_]+)', expr))
            else:
                read |= names
    if not guards:
        print("FAILthe anfitrion family has no absent() guard: every rule in it "
              "compares against a value, so all of them go EMPTY rather than false "
              "when the host stops reporting — and an empty rule looks exactly like a "
              "healthy machine")
    missing = sorted(read - guards)
    if missing:
        print("FAILthe absence guard does not name %s: one probe can die while the "
              "rest keep pushing, and a guard that watches only some of them sleeps "
              "through it" % ", ".join(missing))

print("    %d panel(s) read · %d series read by the anfitrion family, %d named in its "
      "guard" % (panels, len(read) if 'read' in dir() else 0,
                 len(guards) if 'guards' in dir() else 0))
PY
)" || { fail "the reading of the panels and rules could not be completed"; return; }

printf '%s\n' "$OUT" | grep -v '^FAIL'
if printf '%s\n' "$OUT" | grep -q '^FAIL'; then
    fail "the panels and the host family: $(printf '%s\n' "$OUT" | sed -n 's/^FAIL//p' | paste -sd'; ')"
else
    pass "no panel calls the root cgroup the machine, and the host family's guard names every series it reads"
fi
}
