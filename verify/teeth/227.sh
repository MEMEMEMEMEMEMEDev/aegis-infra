# teeth of check 227 — a machine aegis cannot install on is refused before
# anything on it is touched. Every red puts back, in the place it lived, a
# shape that was LIVE on 2026-09-22 when a CachyOS machine got sudoers,
# IPv6 and a half k3s.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
_cut() {   # <file> <from-line-text> <to-line-text> — deletes that block, both ends included
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, a, b = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text(); i = s.index(a); j = s.index(b, i) + len(b)
p.write_text(s[:i] + s[j:])
PYT
}

# the preflight as it was: straight to sudo, no question about the host
red_1() { _cut "$AEGIS_ROOT/libexec/aegis-preflight" '# THE HOST FIRST, before any sudo.' "  exit 1
fi
"; }

# the orchestrator as it was: --from 20 walks around phase 00 into k3s
red_2() { _cut "$AEGIS_ROOT/libexec/aegis-init" 'if ! $DO_LIST && ! host_why=' "nothing was changed on this machine\"
fi
"; }

# phase 00 as it was: it notices, WARNS and goes on
red_3() { _sub "$AEGIS_ROOT/init/phases/00-preflight.sh" \
    'die "$host_why — nothing was changed on this machine"; }' \
    'log_warn "$host_why"; }'; }

# phase 00 asking only after the wizard: every answer wasted
red_4() { python3 - "$AEGIS_ROOT/init/phases/00-preflight.sh" <<'PYT'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
gate = [l for l in s.splitlines(keepends=True) if l.startswith("host_supported 2>/dev/null ||")]
assert len(gate) == 1
s = s.replace(gate[0], "", 1)
anchor = "ensure_config    # defines and validates every var (lib/config.sh)\n"
assert s.count(anchor) == 1
p.write_text(s.replace(anchor, anchor + gate[0], 1))
PYT
}

# any Linux accepted: the CachyOS case itself
red_5() { _sub "$AEGIS_ROOT/lib/host.sh" '[[ "$id" != "ubuntu" ]]' '[[ -z "$id" ]]'; }

# the door lower than the wall: 22.04 let in, the playbook refuses it at phase 20
red_6() { _sub "$AEGIS_ROOT/lib/host.sh" 'AEGIS_HOST_MIN_UBUNTU="24.04"' 'AEGIS_HOST_MIN_UBUNTU="22.04"'; }

# the refusal leaking to stdout, where a $() caller would swallow it
red_7() { _sub "$AEGIS_ROOT/lib/host.sh" \
    "(it uses apt and Ubuntu's kernel and AppArmor defaults)\" >&2" \
    "(it uses apt and Ubuntu's kernel and AppArmor defaults)\""; }

# control: a COMMENT that mentions sudo above the question is prose, not
# an action; a check that read it would forbid explaining the order
control_1() { _sub "$AEGIS_ROOT/libexec/aegis-preflight" \
    '# THE HOST FIRST, before any sudo.' \
    '# (a note: never call sudo here before the host is known)
# THE HOST FIRST, before any sudo.'; }

# control: a newer Ubuntu joins the tested list; nothing about the order changes
control_2() { _sub "$AEGIS_ROOT/init/phases/00-preflight.sh" '        24.04|26.04) ;;' '        24.04|26.04|26.10) ;;'; }
