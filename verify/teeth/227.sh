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

# any Linux accepted: the CachyOS case itself (the family is never
# compared with the list)
red_5() { _sub "$AEGIS_ROOT/lib/host.sh" \
    'if [[ " ${list[*]} " != *" $fam "* ]]; then' 'if false; then'; }

# the door lower than the wall: 22.04 let in, the playbook refuses it at phase 20
red_6() { _sub "$AEGIS_ROOT/lib/host.sh" 'AEGIS_HOST_MIN_UBUNTU="24.04"' 'AEGIS_HOST_MIN_UBUNTU="22.04"'; }

# the refusal leaking to stdout, where a $() caller would swallow it
red_7() { _sub "$AEGIS_ROOT/lib/host.sh" \
    "(it installs with that family's package manager, kernel and security defaults)\" >&2" \
    "(it installs with that family's package manager, kernel and security defaults)\""; }

# ── 2026-09-23: families, and the lab override ─────────────────────
# the override names a family nobody wrote code for, and it is let in
red_8() { _sub "$AEGIS_ROOT/lib/host.sh" \
    'if [[ " $AEGIS_HOST_FAMILIES_KNOWN " != *" $f "* ]]; then' 'if false; then'; }

# Debian 12 let in: python 3.11, and ansible==14 dies in phase 20
red_9() { _sub "$AEGIS_ROOT/lib/host.sh" 'AEGIS_HOST_MIN_DEBIAN="13"' 'AEGIS_HOST_MIN_DEBIAN="12"'; }

# the door opened with no archived run behind it
red_10() { _sub "$AEGIS_ROOT/lib/host.sh" \
    'AEGIS_HOST_SUPPORTED_DEFAULT="ubuntu"' 'AEGIS_HOST_SUPPORTED_DEFAULT="ubuntu debian"'; }

# the playbook lets Debian through whatever the list says
red_11() { _sub "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml" \
    "and 'debian' in (aegis_host_supported | default('ubuntu')).split(','))" "and true)"; }

# phase 20 forgets to pass the list: a lab run stops at the wall
red_12() { _sub "$AEGIS_ROOT/init/phases/20-k3s.sh" \
    '    -e "aegis_host_supported=$AEGIS_HOST_LIST" \
' ''; }

# the widened list goes in silence: a lab run reads like a supported one
red_13() { _sub "$AEGIS_ROOT/lib/host.sh" \
    'echo "note: AEGIS_HOST_SUPPORTED widens the host list' ': "note: AEGIS_HOST_SUPPORTED widens the host list'; }

# a typo in the override keeps the families read before it: half a list
red_14() { _sub "$AEGIS_ROOT/lib/host.sh" \
    'if ! raw="$(host_supported_families)" || [[ -z "$raw" ]]; then' \
    'raw="$(host_supported_families)" || true; if [[ -z "$raw" ]]; then'; }

# a derivative read as its parent: Pop!_OS 24.04 walks in as Ubuntu
red_15() { _sub "$AEGIS_ROOT/lib/host.sh" \
    "        *\" arch \"*) printf 'arch\\n' ;;" \
    "        *\" arch \"*) printf 'arch\\n' ;;
        *\" ubuntu \"*) printf 'ubuntu\\n' ;;"; }

# control: a COMMENT that mentions sudo above the question is prose, not
# an action; a check that read it would forbid explaining the order
control_1() { _sub "$AEGIS_ROOT/libexec/aegis-preflight" \
    '# THE HOST FIRST, before any sudo.' \
    '# (a note: never call sudo here before the host is known)
# THE HOST FIRST, before any sudo.'; }

# control: a newer Ubuntu joins the tested list; nothing about the order changes
control_2() { _sub "$AEGIS_ROOT/init/phases/00-preflight.sh" \
    '        ubuntu:24.04|ubuntu:26.04|debian:13) ;;' '        ubuntu:24.04|ubuntu:26.04|ubuntu:26.10|debian:13) ;;'; }

# control: a COMMENT in the playbook with a lower Debian floor is prose;
# the check reads the assert, not what somebody wrote above it
control_3() { _sub "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml" \
    "    - name: Assert supported distro" \
    "    # (Debian 12 was: distribution'] == 'Debian' and ansible_facts['distribution_major_version'] is version('12', '>='))
    - name: Assert supported distro"; }
