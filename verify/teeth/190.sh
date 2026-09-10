# teeth of check 190 — the machine is measured in one place, written
# down, and never invented where it could not be read.

# THE STATE THE PRODUCT WAS IN, put back: preflight takes its own
# reading of MemTotal, compares it, prints it and forgets it. That was
# the only reading of RAM in the whole artifact on 2026-09-09, and it
# is why the freeze it should have predicted left no record.
red_1() {
    sed -i 's|^HOST_FACTS=.*|mem_g=$(awk "/MemTotal/{printf \\"%d\\", \$2/1024/1024}" /proc/meminfo); HOST_FACTS=""|' \
        "$AEGIS_ROOT/libexec/aegis-preflight"
}

# the ledger of what could not be measured, gone. Without it a null in
# host.json is indistinguishable from a zero, and the whole honesty
# rule collapses into a tidy report with holes in it.
red_2() {
    python3 - "$AEGIS_ROOT/libexec/aegis-host" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("undetermined = sorted(k for k, v in facts.items() if v is None)",
              "undetermined = []")
open(p, "w", encoding="utf-8").write(s)
PY
}

# the write stops being atomic. host.json is what the kubelet's
# reservation and the desktop's floor are derived from: read half
# written, it does not look broken, it looks like a smaller machine.
red_3() {
    python3 - "$AEGIS_ROOT/libexec/aegis-host" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("        tmp.write_text(text, encoding=\"utf-8\")\n        os.replace(tmp, dest)",
              "        dest.write_text(text, encoding=\"utf-8\")")
open(p, "w", encoding="utf-8").write(s)
PY
}

# a probe that could not measure hands back a helpful zero. This is the
# substitution the whole area exists to forbid: downstream, a zero and
# a measurement are the same shape.
red_4() {
    python3 - "$AEGIS_ROOT/libexec/aegis-host" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("    return st.f_bavail * st.f_frsize",
              "    return st.f_bavail * st.f_frsize or 0")
open(p, "w", encoding="utf-8").write(s)
PY
}

# the first reader stops consuming the measurement. A reader that does
# not read is a second measurer waiting to happen.
red_5() {
    sed -i 's|"\$AEGIS_ROOT/libexec/aegis-host" measure --json|true --json|' \
        "$AEGIS_ROOT/libexec/aegis-preflight"
}

# and the check's own subject taken away: with no measure() to inspect,
# finding no defect must NOT be reported as everything fine.
red_6() {
    sed -i 's|^def measure(args):|def medir(args):|' "$AEGIS_ROOT/libexec/aegis-host"
}

# control: prose that NAMES /proc/meminfo without reading it. The
# comment in aegis-preflight explaining why the line was removed must
# not turn the file back into a second measurer — six repetitions of
# reading prose as code are on this project's record.
control_1() {
    printf '\n# a legitimate note: MemTotal and /proc/meminfo are read by aegis-host\n' \
        >> "$AEGIS_ROOT/libexec/aegis-preflight"
}

# control: one more probe, written the way the rule asks — returning
# None when it cannot measure. Growing the profile has to stay green.
control_2() {
    python3 - "$AEGIS_ROOT/libexec/aegis-host" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("def probe_cgroup_v2():",
              "def probe_uptime_seconds():\n"
              "    txt = _read(\"/proc/uptime\")\n"
              "    if txt is None:\n"
              "        return None\n"
              "    try:\n"
              "        return int(float(txt.split()[0]))\n"
              "    except (IndexError, ValueError):\n"
              "        return None\n\n\n"
              "def probe_cgroup_v2():")
open(p, "w", encoding="utf-8").write(s)
PY
}
