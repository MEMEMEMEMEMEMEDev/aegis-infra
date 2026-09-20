# teeth for 217 — each red hands systemd a per cent that was meant for
# something else. The first one is the bug that happened.
N217="$AEGIS_ROOT/share/systemd/aegis-update-notice.service"
B217="$AEGIS_ROOT/share/systemd/aegis-backup.service"
H217="$AEGIS_ROOT/share/systemd/aegis-host-metrics.service"

# the bug itself, verbatim: printf's conversion becomes the user's shell
red_1() { python3 - "$N217" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'printf "%%s" "$m"'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, 'printf "%s" "$m"', 1))
P
}

# a per cent meant for a shell format string, in another unit
red_2() { python3 - "$H217" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'ExecStart=/bin/sh -c '
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, 'ExecStart=/bin/sh -c \'date +%H:%M >/dev/null\'; ExecStart=/bin/sh -c ', 1))
P
}

# a specifier nobody asked for, in a directive that is not a command
red_3() { python3 - "$B217" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '[Service]'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '[Service]\nEnvironment=AEGIS_UNIT=%n', 1))
P
}

# a per cent followed by nothing systemd knows: the unit does not even
# start, and a check that only looked for KNOWN specifiers would miss it
red_4() { python3 - "$N217" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'Nice=10'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, 'Environment=AEGIS_PCT=100%\nNice=10', 1))
P
}

# ── controls ──
# the comment that EXPLAINS the trap is prose, per cents and all
control_1() { printf '\n# note: in a unit file `%%s` is the user shell and `%%%%s` is printf s.\n' >> "$N217"; }
# `%h` is a specifier this artifact asks for on purpose, in one more unit
control_2() { python3 - "$B217" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '[Service]'
assert s.count(old) == 1
p.write_text(s.replace(old, '[Service]\nWorkingDirectory=%h\n', 1))
P
}
# the description of a unit reads better; no directive moves
control_3() { sed -i 's/^Description=aegis: notice what is behind.*/Description=aegis: notice what is behind, and never act on it (daily)/' "$N217"; }
