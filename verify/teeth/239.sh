# teeth of check 239 — no sbin-only tool is called bare.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}

# phase 87 as it was: a bare sysctl, «command not found» read as 0
red_1() { _sub "$AEGIS_ROOT/init/phases/87-ai.sh" \
    'n="$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)"' \
    'n="$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)"'; }

# the same, in a command handed over as a string (gate_diag runs it)
red_2() { _sub "$AEGIS_ROOT/init/phases/87-ai.sh" \
    """'echo \"  fs.inotify.max_user_instances = \$(cat /proc/sys/fs/inotify/max_user_instances 2>&1)\";""" \
    """'sysctl fs.inotify.max_user_instances 2>&1;"""; }

# the preflight's visudo taken out of its `sudo bash -c`
red_3() { _sub "$AEGIS_ROOT/libexec/aegis-preflight" \
    '    && chmod 0440 /etc/sudoers.d/010-aegis-init-nopasswd && visudo -c >/dev/null"' \
    '    && chmod 0440 /etc/sudoers.d/010-aegis-init-nopasswd"
visudo -c >/dev/null'; }

# control: sudo in front is the fix, not a finding
control_1() { _sub "$AEGIS_ROOT/init/phases/87-ai.sh" \
    'n="$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)"' \
    'n="$(sudo -n sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)"'; }

# control: a comment that names a bare sysctl is prose
control_2() { _sub "$AEGIS_ROOT/init/phases/87-ai.sh" \
    '        # /proc, not sysctl: sysctl lives in /usr/sbin' \
    '        # (was: n="$(sysctl -n fs.inotify.max_user_instances)")
        # /proc, not sysctl: sysctl lives in /usr/sbin'; }
