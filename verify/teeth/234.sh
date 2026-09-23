# teeth of check 234 — the Access half of a dirty cloud.

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PYT'
import sys, pathlib
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
assert s.count(old) == 1, f"{p}: {s.count(old)} occurrences of the anchor"
p.write_text(s.replace(old, new, 1))
PYT
}
PH234="$AEGIS_ROOT/init/phases/25-edge-tofu.sh"

# the phase as it was on 2026-09-23 07:56: listed, never deleted
red_1() { _sub "$PH234" '                _cf_access -X DELETE "$CFB/accounts/$CF_ACCOUNT_ID/access/$kind/$id" \' '                printf %s '"'"'{"success":true}'"'"' \'; }

# the applications stop matching the zone: the very 409 of that morning
red_2() { _sub "$PH234" '+ "(/|$)")'"'"' || exit 2' '+ "(/|\$never)")'"'"' || exit 2'; }

# a policy renamed in the phase and not in the module
red_3() { _sub "$PH234" 'ACCESS_POLICY_NAMES="aegis-operador aegis-automatizacion aegis-webhook-publico"' 'ACCESS_POLICY_NAMES="aegis-operator aegis-automatizacion aegis-webhook-publico"'; }

# the gate gone: a surviving leftover is nobody's failure
red_4() { _sub "$PH234" '        gate "access-sin-restos" _access_swept' '        :'; }

# the state ignored: the sweep eats this instance's own policies
red_5() { _sub "$PH234" '            grep -qxF "$id" <<< "$known" && continue' '            :'; }

# control: the same sweep, a different word in the log
control_1() { _sub "$PH234" '                log_ok "Access $kind $label deleted"' '                log_ok "Access $kind $label removed from the account"'; }
