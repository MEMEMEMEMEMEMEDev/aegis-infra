# teeth of check 241 — every family with code has its branch everywhere.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
RHT="$AEGIS_ROOT/seed/platform/ansible/playbooks/registry-host-trust.yml"

# arch opens with the CA written where only debian looks
red_1() { _sub "$RHT" \
    '          Archlinux: /etc/ca-certificates/trust-source/anchors/aegis-internal-ca.crt
' ''; }

# the anchor written and the bundle never rebuilt on arch
red_2() { _sub "$RHT" \
    "\"{{ 'update-ca-trust' if ansible_facts['os_family'] == 'Archlinux' else 'update-ca-certificates' }}\"" \
    "update-ca-certificates"; }

# the arch base packages task gone
red_3() { _sub "$AEGIS_ROOT/seed/platform/ansible/playbooks/bootstrap-host.yml" \
    "      when: ansible_facts['os_family'] == 'Archlinux'
" ""; }

# tofu back to .deb only
red_4() { _sub "$AEGIS_ROOT/init/phases/05-host.sh" \
    '"$GH_REL/opentofu/opentofu/releases/download/v${pin}/tofu_${pin}_linux_amd64.tar.gz" \' \
    '"$GH_REL/opentofu/opentofu/releases/download/v${pin}/tofu_${pin}_amd64.deb" \'; }

# the clock repair that restarts a unit arch does not have
red_5() { _sub "$AEGIS_ROOT/libexec/aegis-preflight" \
    '{ sudo systemctl restart chrony || sudo systemctl restart chronyd; } >/dev/null 2>&1' \
    'sudo systemctl restart chrony >/dev/null 2>&1'; }

# a CA anchor without .crt: update-ca-certificates skips it in silence
red_6() { _sub "$RHT" \
    '          Debian: /usr/local/share/ca-certificates/aegis-internal-ca.crt' \
    '          Debian: /usr/local/share/ca-certificates/aegis-internal-ca.pem'; }

# control: a comment naming the old single path is prose
control_1() { _sub "$RHT" \
    "      # WHERE depends on the family:" \
    "      # (was: dest: /usr/local/share/ca-certificates/aegis-internal-ca.crt, for every host)
      # WHERE depends on the family:"; }
