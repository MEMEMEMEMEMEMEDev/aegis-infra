# teeth of check 280 — the node defends its disk, and warns before it has to.
H280="$AEGIS_ROOT/lib/aegis/host.py"
P280="$AEGIS_ROOT/init/phases/20-k3s.sh"
R280="$AEGIS_ROOT/seed/platform/k8s/base/observability/rules/vmalert-rules.yaml"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# the drop-in as it was from 2026-09-10: memory only, the disk defaults switched off
red_1() { _sub "$H280" '        '"'"'  - "eviction-hard=%s"'"'"' % ",".join(
            ("memory.available<%s" % r["eviction"],) + DISK_EVICTION),' '        '"'"'  - "eviction-hard=memory.available<%s"'"'"' % r["eviction"],'; }

# the images' signal forgotten
red_2() { _sub "$H280" '                 "imagefs.available<15%", "imagefs.inodesFree<5%")' '                 "imagefs.inodesFree<5%",)'; }

# phase 20 trusts the file instead of the kubelet
red_3() { _sub "$P280" 'gate "kubelet-desaloja-por-disco" retry_net 3 _kubelet_evicts_on_disk' 'gate "kubelet-desaloja-por-disco" sudo -n test -f "$AEGIS_RESERVED_FILE"'; }

# the host stops publishing the disk
red_4() { _sub "$AEGIS_ROOT/libexec/aegis-host" '        emit("aegis_host_disk_free_bytes", st.f_bavail * st.f_frsize, {"mount": mount},
             help_="bytes an unprivileged writer can still use there")
' ''; }

# the warning arrives after the eviction
red_5() { _sub "$R280" 'last_over_time(aegis_host_disk_size_bytes[5m])) < 0.20' 'last_over_time(aegis_host_disk_size_bytes[5m])) < 0.05'; }

# the disk alert goes mute when its series stops
red_6() { _sub "$R280" ' or absent(last_over_time(aegis_host_disk_free_bytes[15m]))' ''; }

# ── controls ──
control_1() { _sub "$R280" 'last_over_time(aegis_host_disk_size_bytes[5m])) < 0.20' 'last_over_time(aegis_host_disk_size_bytes[5m])) < 0.25'; }
