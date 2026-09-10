# teeth of check 195 — the host reports on itself with watermarks and
# counters, on a clock its readers can follow, and fails loudly.

# THE BLINDNESS THAT MAKES A SAMPLER USELESS: reading the gauge instead
# of the watermark. Once a minute cannot see a start-up spike that
# lasted eight seconds, and the graph it draws of a machine that was
# swapping is a calm one.
red_1() {
    sed -i 's|peak if isinstance(peak, int) else None, {"slice": name},|None, {"slice": name},|' \
        "$AEGIS_ROOT/libexec/aegis-host"
    sed -i '/^             cur if isinstance(cur, int) else None, {"slice": name},$/!b' \
        "$AEGIS_ROOT/libexec/aegis-host"
    python3 - "$AEGIS_ROOT/libexec/aegis-host" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('"aegis_host_cgroup_memory_peak_bytes"', '"aegis_host_cgroup_memory_second_bytes"')
s = s.replace('peak_bytes', 'segundo_bytes')
open(p, "w", encoding="utf-8").write(s)
PY
}

# VRAM published with no watermark of its own. nvidia-smi keeps none,
# so the instant the desktop and both engines wanted the card at once
# simply is not in the record — the instant that killed a session on
# 2026-09-06.
red_2() {
    python3 - "$AEGIS_ROOT/libexec/aegis-host" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('    emit("aegis_host_vram_peak_mib", _vram_watermark(used_mib),\n'
              '         help_="the most VRAM seen in use — a gauge with no kernel-side mark, so this keeps its own")\n', "")
s = s.replace("def _vram_watermark(now):", "def _marca_de_agua_vram(now):")
open(p, "w", encoding="utf-8").write(s)
PY
}

# the floor read back from the file this product wrote instead of from
# the kernel. A drop-in that never took effect looks identical to one
# that did, if you only read your own writing.
red_3() {
    sed -i 's|    live = _read("/sys/fs/cgroup/user.slice/memory.min")|    live = _read(str(paths.aegis_home() / "host-floor"))|' \
        "$AEGIS_ROOT/libexec/aegis-host"
}

# the clock slower than the windows that read it. One late push and
# every rule in the family empties — and an empty rule looks exactly
# like a healthy machine.
red_4() {
    sed -i 's|^OnUnitActiveSec=60s$|OnUnitActiveSec=10min|' \
        "$AEGIS_ROOT/share/systemd/aegis-host-metrics.timer"
}

# the push allowed to fail in silence. The backup unit is right to use
# a leading `-`; here the measurement IS the work.
red_5() {
    sed -i 's|^ExecStart=/bin/sh|ExecStart=-/bin/sh|' \
        "$AEGIS_ROOT/share/systemd/aegis-host-metrics.service"
}

# and the check's own subject taken away: with metrics() renamed,
# finding no defect must NOT read as everything fine.
red_6() {
    sed -i 's|^def metrics(args):|def metricas(args):|' "$AEGIS_ROOT/libexec/aegis-host"
}

# control: one more series, published the way the rule asks.
control_1() {
    python3 - "$AEGIS_ROOT/libexec/aegis-host" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('    emit("aegis_host_metrics_timestamp_seconds"',
              '    emit("aegis_host_cpus", probe_cpus(),\n'
              '         help_="threads the machine has")\n'
              '    emit("aegis_host_metrics_timestamp_seconds"')
open(p, "w", encoding="utf-8").write(s)
PY
}

# control: prose in the unit naming a leading dash without using one.
# The comment explains at length why this push must NOT be prefixed,
# and an explanation must not be read as the thing it warns against.
control_2() {
    printf '\n# a legitimate note: ExecStartPost=- is what the backup unit uses.\n' \
        >> "$AEGIS_ROOT/share/systemd/aegis-host-metrics.service"
}

# THE HEADLESS SERVICE, unhandled. vmsingle has `clusterIP: None`, so
# reading that jsonpath yields the four characters N-o-n-e and curl
# tries to resolve a host by that name. Measured 2026-09-10 — and the
# backup unit had carried exactly this bug since it was written,
# silently, because its `-` prefix swallowed the failure: the instance
# had zero aegis_backup_remote_* series while three alerts read them.
red_7() {
    python3 -c '
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("""&& [ "$ip" = "None" ] && ip=$(kubectl get endpointslice -n observability -l kubernetes.io/service-name=vmsingle -o jsonpath="{.items[0].endpoints[0].addresses[0]}"); pt=""", "&& pt=")
open(p, "w", encoding="utf-8").write(s)
' "$AEGIS_ROOT/share/systemd/aegis-host-metrics.service"
}
