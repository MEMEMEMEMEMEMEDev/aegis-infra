# teeth of check 238 — the preflight asks the resolver every program uses.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}

# the probe as it was on 2026-09-22: systemd-resolved's tool, «command
# not found» on Debian 13 and Arch
red_1() { _sub "$AEGIS_ROOT/libexec/aegis-preflight" \
    'do getent ahosts github.com >/dev/null 2>&1 && R=$((R+1)); done' \
    'do resolvectl query github.com >/dev/null 2>&1 && R=$((R+1)); done'; }

# a probe that counts without asking: green on a host with no DNS at all
red_2() { _sub "$AEGIS_ROOT/libexec/aegis-preflight" \
    'do getent ahosts github.com >/dev/null 2>&1 && R=$((R+1)); done' \
    'do getent ahosts github.com >/dev/null 2>&1; R=$((R+1)); done'; }

# control: a COMMENT naming resolvectl query is prose, not the probe
control_1() { _sub "$AEGIS_ROOT/libexec/aegis-preflight" \
    '# The probe asks the resolver every program on this host uses' \
    '# (it used to be: resolvectl query github.com)
# The probe asks the resolver every program on this host uses'; }
