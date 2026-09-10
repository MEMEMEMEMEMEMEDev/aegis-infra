# teeth of check 194 — the desktop's floor is generated from the
# measurement, applied by a verb that can undo it, and verified against
# the kernel.

# THE FLOOR WRITTEN DOWN INSTEAD OF DERIVED. It is a number per
# machine — the step from plans.yaml, the RAM from the measurement —
# and a fixed one in a phase is the copy that drifts the first time
# somebody installs on a laptop.
red_1() {
    printf '\n[Slice]\nMemoryMin=4294967296\n' \
        >> "$AEGIS_ROOT/share/systemd/aegis-host-metrics.service"
}

# the same, one layer up: a phase that writes the number itself.
red_2() {
    printf '\n# applying the floor\necho "MemoryMin=6442450944" | sudo tee /etc/systemd/system/user.slice.d/floor.conf\n' \
        >> "$AEGIS_ROOT/init/phases/05-host.sh"
}

# the way back removed. A protection that cannot be lifted in one
# command is one nobody dares switch on — and this one can starve a
# cluster if the step is wrong.
red_3() {
    python3 - "$AEGIS_ROOT/libexec/aegis-host" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('    p.add_argument("--off", action="store_true",\n'
              '                   help="lift the floor: removes the drop-in, restarts nothing")\n', "")
s = s.replace("--off", "--desactivar")
open(p, "w", encoding="utf-8").write(s)
PY
}

# the floor read back from the file we just wrote instead of from the
# kernel. systemd accepts a drop-in on a slice that is not accounting
# memory and says nothing; confirming our own writing confirms nothing.
red_4() {
    python3 - "$AEGIS_ROOT/lib/aegis/host.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('FLOOR_LIVE = "/sys/fs/cgroup/user.slice/memory.min"',
              'FLOOR_LIVE_FILE = "/etc/systemd/system/user.slice.d/10-aegis-desktop-floor.conf"')
open(p, "w", encoding="utf-8").write(s)
PY
}

# a drop-in on kubepods.slice: the kubelet creates that unit as
# transient, stamps it "Do not edit", and regenerates it from
# allocatable on every start. Two authors, one file.
red_5() {
    printf '\n# the cluster ceiling\nsudo mkdir -p /etc/systemd/system/kubepods.slice.d\n' \
        >> "$AEGIS_ROOT/init/phases/05-host.sh"
}

# the guard against an absurd floor removed: held irreclaimable, a
# floor bigger than the machine has the kernel reclaiming pods to
# honour a desktop that is not asking for anything — an outage with a
# friendly name.
#
# It deletes the COMPARISON and not the flag. Renaming `--force` was
# the first attempt and it did not bite, because the word survived
# elsewhere in the file: the guard is the arithmetic, never the
# vocabulary around it.
red_6() {
    python3 -c '
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r"    ram = facts\.get\(\"ram_total_bytes\"\)\n(?:.*\n)*?        return 1\n",
           "", s, count=1)
open(p, "w", encoding="utf-8").write(s)
' "$AEGIS_ROOT/libexec/aegis-host"
}

# control: prose in a phase EXPLAINING that the floor is applied with a
# verb. Naming MemoryMin is not writing one.
control_1() {
    printf '\n# a legitimate note: the floor (MemoryMin on user.slice) is applied by\n# `aegis host floor --apply`, never from here.\n' \
        >> "$AEGIS_ROOT/init/phases/05-host.sh"
}

# control: prose naming kubepods.slice to explain why it is left alone.
control_2() {
    printf '\n# a legitimate note: no drop-in is written for kubepods.slice — the\n# kubelet owns that unit and regenerates it from allocatable.\n' \
        >> "$AEGIS_ROOT/lib/aegis/host.py"
}

# control: another generated line in the drop-in, written the way the
# rule asks. Growing the fragment has to stay green.
control_3() {
    sed -i 's|        f"MemoryMin={f\[.ram_bytes.\]}\\n")|        f"MemoryMin={f[\x27ram_bytes\x27]}\\n"\n        "MemoryPressureWatch=auto\\n")|' \
        "$AEGIS_ROOT/lib/aegis/host.py"
}
