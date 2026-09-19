# teeth for 215 — the measurement and the watching must not drift, and
# the clock must not be able to act.
U215="$AEGIS_ROOT/libexec/aegis-update"
R215="$AEGIS_ROOT/seed/platform/k8s/base/observability/rules/vmalert-rules.yaml"
S215="$AEGIS_ROOT/share/systemd/aegis-update-notice.service"
T215="$AEGIS_ROOT/share/systemd/aegis-update-notice.timer"

# a series the alerts read stops being published: the rule goes empty,
# and empty looks exactly like a healthy platform
red_1() { python3 - "$U215" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        emit("aegis_update_pins_gone", d["gone"], lab,'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '        emit("aegis_update_pins_vanished", d["gone"], lab,', 1))
P
}

# a series is published that nothing reads: dead weight wearing the
# shape of coverage
red_2() { python3 - "$U215" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        emit("aegis_update_pins_behind", d["behind"], lab,'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, '''        emit("aegis_update_pins_interesting", d["total"], lab,
             "a number somebody thought was interesting")
        emit("aegis_update_pins_behind", d["behind"], lab,''', 1))
P
}

# the family loses the sibling that watches its own silence: when the
# producer stops, every rule goes quiet and the panel stays calm
red_3() { python3 - "$R215" <<'P'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
i = s.index("          - alert: UpdateMeasurementStopped")
p.write_text(s[:i])
P
}

# nothing reminds anybody that a window is due
red_4() { sed -i 's/- alert: UpdateWindowDue/- alert: UpdateWindowMaybe/' "$R215"; }

# the clock opens the window: the one thing the operator said it must
# never do
red_5() { python3 - "$S215" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'm=$(/usr/local/bin/aegis update metrics)'
assert s.count(old) == 1, "re-aim this tooth"
p.write_text(s.replace(old, 'm=$(/usr/local/bin/aegis update window --yes)', 1))
P
}

# a missed run is simply lost: a laptop closed for four days stops
# measuring and the panel keeps showing last week's number
red_6() { sed -i 's/^Persistent=true$/Persistent=false/' "$T215"; }

# ── controls ──
# the HELP of a series is prose; the series is what is read
control_1() { python3 - "$U215" <<'P'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '"pins whose tag no longer exists upstream: what runs here cannot be rebuilt"'
assert s.count(old) == 1
p.write_text(s.replace(old, '"pins whose tag has vanished upstream: this platform cannot be rebuilt"', 1))
P
}
# the wording of an alert's description changes; what it reads does not
control_2() { sed -i 's/Nothing is broken. `aegis update plan`/Nothing is wrong here. `aegis update plan`/' "$R215"; }
# a comment in the unit naming the forbidden verb is prose, not a verb
control_3() { printf '\n# note: this unit never runs `aegis update window`, with or without --yes.\n' >> "$S215"; }
