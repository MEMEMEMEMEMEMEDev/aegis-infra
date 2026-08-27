# teeth for check 142 (the wizard writes where nothing exists yet, and checks it)
# generated on 2026-08-27 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
# The three silences of the first VPS run, each put back on purpose.
CS="lib/config.sh"

# the directory is not created: on a clean machine the mv has nowhere to go
red_1() {
    python3 - "$AEGIS_ROOT/$CS" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    mkdir -p "$(dirname "$CONF_FILE")" \\\n        || { rm -f "$tmp"; die "could not create $(dirname "$CONF_FILE") for the config"; }\n'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "", 1))
PY
}
# the mv loses its || die: a failed write is followed by "config written"
red_2() {
    python3 - "$AEGIS_ROOT/$CS" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    mv "$tmp" "$CONF_FILE" \\\n        || { rm -f "$tmp"; die "could not write $CONF_FILE (the answers were NOT saved)"; }\n'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, '    mv "$tmp" "$CONF_FILE"\n', 1))
PY
}
# config_validate sources a file that may not be there
red_3() {
    python3 - "$AEGIS_ROOT/$CS" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = '    [[ -f "$CONF_FILE" ]] || { log_warn "no config at $CONF_FILE"; return 1; }\n'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "", 1))
PY
}
# control: the message is not the contract
control_1() {
    python3 - "$AEGIS_ROOT/$CS" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = 'log_ok "config written to $CONF_FILE"'
assert t.count(old) == 1
open(p, "w").write(t.replace(old, 'log_ok "config saved at $CONF_FILE"', 1))
PY
}
