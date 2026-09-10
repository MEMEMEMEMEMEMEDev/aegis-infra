# title: the node's reservation is a derived drop-in, written unconditionally, and taken back out if the node does not return
# origin: new in v3 — measured on 2026-09-09: allocatable == capacity, on a machine with a person using it
check() {
# The node reported `allocatable == capacity` (31688052Ki) and
# `kubepods.slice/memory.max` was 32448565248 — exactly the machine. So
# the scheduler believed it could hand out every byte, and the kernel
# let the cluster reach for all of it, on a computer somebody was
# sitting at.
#
# ONE NUMBER FIXES BOTH, which is why it is derived rather than written
# anywhere: `system-reserved` lowers `allocatable`, and with
# `enforce-node-allocatable=pods` the kubelet writes kubepods.slice's
# own ceiling from the SAME subtraction. The ceiling is a consequence
# of the floor and cannot drift away from it.
#
# Four things are demanded of how it lands:
#
#   1 · A DROP-IN, NOT AN EDIT of /etc/rancher/k3s/config.yaml. That
#     file already has an owner — the task that pins `resolv-conf`,
#     whose three literal lines check 024 greps for — and it is written
#     only when systemd-resolved is present. Putting a memory
#     reservation there would mean rewriting somebody else's task, or
#     hanging it off a condition that has nothing to do with it.
#
#   2 · WRITTEN UNCONDITIONALLY, except for having a value. Hanging it
#     off `resolved_real` is the trap that made the drop-in necessary
#     in the first place.
#
#   3 · NO NUMBERS IN THE PLAYBOOK. The content arrives as a variable
#     the init derives; a literal `system-reserved=` in ansible is the
#     copy that drifts from the machine it was written for.
#
#   4 · AND IT COMES BACK OUT BY ITSELF. A malformed `kubelet-arg`
#     stops k3s from starting. A node is worth more than a reservation,
#     so the phase restarts, waits a bounded time, and on silence
#     removes the drop-in and restarts again rather than leaving a
#     machine down with a tidy config file on it.
PB="$P/ansible/playbooks/bootstrap-host.yml"
PH="$PHASES/20-k3s.sh"
for f in "$PB" "$PH"; do
    [[ -f "$f" ]] || { fail "$f is not there"; return; }
done

OUT="$(python3 - "$PB" "$PH" <<'PY'
import re, sys, yaml

pb_raw = open(sys.argv[1], encoding="utf-8").read()
ph = open(sys.argv[2], encoding="utf-8").read()
ph_code = "\n".join(l.split("#", 1)[0] for l in ph.splitlines())

try:
    plays = yaml.safe_load(pb_raw)
except yaml.YAMLError as e:
    print(f"FAILbootstrap-host.yml could not be parsed ({e!r}): with no tasks readable "
          "every rule below would look satisfied")
    raise SystemExit

tasks = []
for play in plays or []:
    tasks += (play.get("tasks") or [])

# The task that WRITES the drop-in, not merely one that mentions the
# directory: the playbook also creates config.yaml.d/ with `file:`, and
# picking that one made every rule below report about the wrong task.
def dest_of(t):
    c = t.get("ansible.builtin.copy") or t.get("copy") or {}
    return str(c.get("dest", ""))

reserved = [t for t in tasks if "config.yaml.d/" in dest_of(t)]
if not reserved:
    print("FAILno task writes into /etc/rancher/k3s/config.yaml.d: the node keeps "
          "nothing back for the machine it lives on, and the scheduler goes on "
          "believing it owns every byte")
    raise SystemExit
t = reserved[0]
copy = t.get("ansible.builtin.copy") or t.get("copy") or {}
dest = str(copy.get("dest", ""))
content = str(copy.get("content", ""))
when = str(t.get("when", ""))

# 1 · a drop-in and not the file with an owner
if "config.yaml.d" not in dest:
    print("FAILthe reservation is not written into config.yaml.d/ but into %r: that "
          "file already has an owner and a condition of its own" % dest)
for other in tasks:
    d = str((other.get("ansible.builtin.copy") or other.get("copy") or {}).get("dest", ""))
    c = yaml.safe_dump(other)
    if d.endswith("/config.yaml") and re.search(r'system-reserved|kubelet-arg', c):
        print("FAILthe task that owns config.yaml now also carries the reservation: "
              "check 024 greps that task literally, and a memory reservation has no "
              "business depending on whether this host runs systemd-resolved")

# 2 · unconditional except for having a value
if "resolved_real" in when:
    print("FAILthe reservation is written only `when: %s`: on a host without "
          "systemd-resolved it would silently keep nothing back, which is the exact "
          "gap that made a separate drop-in the right shape" % when)
if "aegis_node_reserved" not in when:
    print("FAILthe reservation task is not guarded by having a value: with an empty "
          "variable it would write an empty file, and an empty drop-in is not the "
          "same as no reservation — one looks configured")

# 3 · no numbers in the playbook
if not re.search(r'\{\{\s*aegis_node_reserved\s*\}\}', content):
    print("FAILthe drop-in's content is not the derived variable: a literal in ansible "
          "is a number written for one machine and applied to every other")
for m in re.finditer(r'(system-reserved|eviction-hard)=[^\s"\']*\d', content):
    print("FAILthe playbook writes %r itself: the arithmetic belongs to `aegis host`, "
          "which is the only thing that has measured this machine" % m.group(0))

# 4 · the phase derives it, and can take it back
if "reservation --for kubelet" not in ph_code:
    print("FAILphase 20 does not ask `aegis host reservation --for kubelet`: the "
          "playbook is deliberately dumb, so if the phase does not derive the value "
          "nothing does")
if "aegis_node_reserved" not in ph_code:
    print("FAILphase 20 never passes aegis_node_reserved to the playbook: the task "
          "would find no value and write nothing, silently")
# the valve: something has to remove the drop-in when the node does not
# come back. Its shape is free; its existence is not.
if not re.search(r'rm -f[^\n]*AEGIS_RESERVED_FILE|rm -f[^\n]*config\.yaml\.d', ph_code):
    print("FAILnothing removes the drop-in when the node does not return: a malformed "
          "kubelet-arg stops k3s from starting, and a node is worth more than a "
          "reservation")
elif not re.search(r'wait_for\s+\d+', ph_code):
    print("FAILthe rollback is not bounded by a wait: without a timeout it either "
          "never fires or fires immediately, and neither is a valve")
else:
    # EVERY wait_for HERE HAS TO CARRY ITS LABEL. The signature is
    # `wait_for TIMEOUT EVERY WHAT cmd...` -- three arguments before the
    # command -- and on 2026-09-10 the first version of this valve passed
    # `kubectl` as the label. The command it actually polled was
    # `get --raw=/readyz`, which is not a command, so the probe could
    # only ever answer NO: the valve fired after 180 s and rolled back a
    # reservation that was working, on a cluster that was healthy the
    # whole time.
    #
    # A valve whose probe cannot say YES is not a safety net. It is a
    # switch that turns the feature off on a timer, and it looks exactly
    # like a safety net that saved you.
    for m in re.finditer(r'wait_for\s+\d+\s+\d+\s+(\S+)', ph_code):
        third = m.group(1)
        if not (third.startswith('"') or third.startswith("'") or third == "\\"):
            print("FAILa wait_for in phase 20 passes %r where the LABEL goes: the "
                  "signature eats three arguments before the command, so the verb "
                  "after it is swallowed and the probe can only answer no" % third)

print("    the reservation is a derived drop-in in config.yaml.d, guarded by having a "
      "value, with a bounded rollback")
PY
)" || { fail "the reading of the node's reservation could not be completed"; return; }

printf '%s\n' "$OUT" | grep -v '^FAIL'
if printf '%s\n' "$OUT" | grep -q '^FAIL'; then
    fail "the node's reservation: $(printf '%s\n' "$OUT" | sed -n 's/^FAIL//p' | paste -sd'; ')"
else
    pass "the reservation is derived, lands as its own drop-in, is written whenever there is a value, and is withdrawn if the node does not come back"
fi
}
