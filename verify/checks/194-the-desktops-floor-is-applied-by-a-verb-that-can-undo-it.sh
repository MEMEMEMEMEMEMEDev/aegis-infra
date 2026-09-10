# title: the desktop's floor is generated from the measurement, applied by a verb that can undo it, and verified against the kernel
# origin: new in v3 — measured on 2026-09-09: user.slice had memory.min = 0 and the kernel evicted the human
check() {
# The mechanism of the freeze, in one line of /sys: `user.slice` had
# `memory.min = 0`. Nothing guaranteed the person anything, so under
# pressure the kernel reclaimed from the session — not from the pods,
# which were all comfortably under their limits. Nothing was OOM
# killed. Nothing had to be.
#
# Four properties of the cure, and three of them are about being able
# to undo it:
#
#   1 · IT IS GENERATED, NOT SHIPPED. The number is a derivation per
#     machine (the step from plans.yaml, the RAM from the measurement),
#     and this house does not ship derived numbers. A literal
#     `MemoryMin=` in a phase would be the copy that drifts.
#
#   2 · IT COMES BACK OFF IN ONE COMMAND. A protection that cannot be
#     lifted quickly is one nobody dares turn on — and this one can
#     starve a cluster if it is set wrong, so the way back has to be
#     cheaper than the way in.
#
#   3 · IT IS VERIFIED AGAINST THE KERNEL. systemd accepts a drop-in on
#     a slice that is not accounting memory and reports nothing wrong.
#     Reading back the file we just wrote would confirm our own
#     writing; the only honest source is /sys/fs/cgroup. An applied
#     floor that is inert is WORSE than none, because the panel says
#     protected.
#
#   4 · NOTHING TOUCHES kubepods.slice. That one is a transient unit
#     the kubelet creates and stamps "Do not edit", regenerating it
#     from `allocatable` on every start. A drop-in there would make
#     aegis the second author of somebody else's file — the class this
#     tree already refuses for containerd's config. The cluster's
#     ceiling comes from the kubelet's own reservation instead.
CMD="$LIBEXEC/aegis-host"
LIBH="$LIBS/aegis/host.py"
for f in "$CMD" "$LIBH"; do
    [[ -f "$f" ]] || { fail "$f is not there"; return; }
done

OUT="$(python3 - "$CMD" "$LIBH" "$PHASES" "$AEGIS_ROOT/share/systemd" <<'PY'
import pathlib, re, sys

def code(path):
    # errors="replace", and it is not defensiveness for its own sake.
    # This check WALKS trees, and a tree is not the same set of files
    # from one moment to the next: an earlier check runs `bin/aegis`,
    # python writes lib/aegis/__pycache__/*.pyc, and the next walk meets
    # a binary. Measured while writing this check -- it passed alone and
    # failed in the full round, which is the worst way to find out. A
    # reader that cannot read is a verdict about the reader.
    try:
        s = pathlib.Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    s = re.sub(r'"""(?:.|\n)*?"""', "", s)
    return "\n".join(l.split("#", 1)[0] for l in s.splitlines())


def is_source(p):
    """Compiled artefacts are not the artifact."""
    return "__pycache__" not in p.parts and p.suffix not in (".pyc", ".pyo")

cmd, lib = code(sys.argv[1]), code(sys.argv[2])

# 1 · generated from the derivation
if "floor_dropin_text" not in lib:
    print("FAILthe drop-in is not generated from the derivation: the floor is a "
          "number per machine, and a fixed one somewhere is the copy that drifts")
if "MemoryMin=" not in lib:
    print("FAILnothing generates a MemoryMin= line: the floor is declared and never "
          "reaches the kernel")

# ...and NOT written literally into a phase or shipped as a unit
for d, label in ((sys.argv[3], "a phase"), (sys.argv[4], "share/systemd")):
    for p in sorted(pathlib.Path(d).rglob("*")):
        if not p.is_file() or not is_source(p):
            continue
        # ANYWHERE on the line, not only at its start: the number can
        # arrive inside an `echo ... | sudo tee`, which is exactly how
        # somebody would hand-roll this in a phase.
        for m in re.finditer(r'MemoryMin\s*=\s*(\d+)', code(p)):
            print("FAIL%s (%s) writes MemoryMin=%s down: the floor is derived per "
                  "machine from plans.yaml and the measurement, and this house does "
                  "not ship derived numbers" % (p.name, label, m.group(1)))

# 2 · the way back
if "--off" not in cmd:
    print("FAILthere is no `--off`: a protection that cannot be lifted in one command "
          "is one nobody dares switch on, and this one can starve a cluster if the "
          "step is wrong")

# 3 · verified against the kernel and not against our own writing
if "FLOOR_LIVE" not in lib or "/sys/fs/cgroup" not in lib:
    print("FAILthe applied floor is not read back from /sys/fs/cgroup: systemd accepts "
          "a drop-in on a slice that is not accounting memory and says nothing, so "
          "reading our own file back would confirm nothing")
m = re.search(r'^def _floor_report\(.*?\):\n(.*?)(?=\n(?:def|class)\s|\Z)', cmd, re.M | re.S)
if not m:
    print("FAILnothing reports whether the floor took effect: an applied floor that is "
          "inert is worse than none, because it reads as protection")
elif "FLOOR_LIVE" not in m.group(1):
    print("FAIL_floor_report does not read the kernel's own value: it has to compare "
          "against /sys, never against the drop-in it just wrote")

# 4 · kubepods.slice is left alone
for d in (sys.argv[3], sys.argv[4], str(pathlib.Path(sys.argv[1]).parent),
          str(pathlib.Path(sys.argv[2]).parent)):
    for p in sorted(pathlib.Path(d).rglob("*")):
        if not p.is_file() or not is_source(p):
            continue
        if re.search(r'kubepods\.slice\.d|/etc/systemd/[^\n]*kubepods', code(p)):
            print("FAIL%s writes a systemd drop-in for kubepods.slice: the kubelet "
                  "creates that unit as transient, stamps it 'Do not edit' and "
                  "regenerates it from allocatable on every start — a second author "
                  "of somebody else's file" % p.name)

# and the guard against a floor that would starve the cluster. The
# word "force" appearing SOMEWHERE is not the guard — the guard is a
# comparison of the floor against the machine, with a deliberate way
# past it. Measured while writing this check: renaming the flag left
# `force=False` in the file and the naive test stayed green.
w = re.search(r'^def _floor_write\(.*?\):\n(.*?)(?=\n(?:def|class)\s|\Z)', cmd, re.M | re.S)
if not w:
    print("FAILthere is no _floor_write to inspect: nothing applies the floor")
else:
    guard = w.group(1)
    if not re.search(r'ram_total_bytes', guard):
        print("FAILthe application never compares the floor against the machine's RAM: "
              "held irreclaimable, a floor larger than the machine would have the "
              "kernel reclaiming pods to honour a desktop that is not asking for "
              "anything")
    elif not re.search(r'\bforce\b', guard):
        print("FAILthe size guard has no deliberate way past it: a refusal with no "
              "override turns a judgement call into a wall, and the operator who "
              "really means it edits the source instead")

print("    the drop-in is generated, reversible, read back from the kernel, and "
      "kubepods.slice is left to the kubelet")
PY
)" || { fail "the reading of the floor's application could not be completed"; return; }

printf '%s\n' "$OUT" | grep -v '^FAIL'
if printf '%s\n' "$OUT" | grep -q '^FAIL'; then
    fail "the desktop's floor: $(printf '%s\n' "$OUT" | sed -n 's/^FAIL//p' | paste -sd'; ')"
else
    pass "the floor is generated per machine, lifted by one command, verified against the kernel, and never a drop-in on kubepods.slice"
fi
}
