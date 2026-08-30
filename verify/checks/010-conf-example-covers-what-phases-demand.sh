# title: conf.example covers everything the phases demand
# origin: verify-static.sh (v2) ══ 10 — subject derived, 2026-08-29
check() {
# Until 2026-08-29 this check carried a WRITTEN LIST of twelve variable
# names. It was measured that day, when the wizard gained `AI`: the
# variable was added to the wizard, deliberately left out of the
# example, and the check stayed green. A list is a copy of the truth
# that ages the moment somebody adds a question, and it ages silently,
# which is the only way that matters.
#
# So the subject is DERIVED from the one place that already has to be
# right: the loop in `config_wizard` that WRITES the conf. Whatever it
# names is what an instance's conf carries, and therefore exactly what
# the example has to document. `AEGIS_WORKSPACE` is written by its own
# `printf` a few lines below the loop (it carries a literal $HOME that
# must not be expanded), so it is read from there too.
#
# Both directions are measured, and the second is the one that rots
# without anybody looking: a variable documented in the example that
# the wizard no longer writes is a lie in the file people copy in
# order to automate the init.
CONF="$AEGIS_ROOT/init/aegis-init.conf.example"
CFG="$AEGIS_ROOT/lib/config.sh"
[[ -f "$CONF" ]] || { fail "conf.example is not there: $CONF"; return; }
[[ -f "$CFG"  ]] || { fail "lib/config.sh is not there: $CFG"; return; }

# The variables the wizard writes: the `for v in … ; do` inside the
# block that builds the conf, plus every name printf'd as NAME="…".
WRITTEN="$(python3 - "$CFG" <<'PY'
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
# the write block: from the atomic-write comment to the closing of the
# subshell that feeds the temp file
m = re.search(r'atomic write of the \.conf.*?\n\s*\}\s*>\s*"\$tmp"', src, re.S)
body = m.group(0) if m else ''
names = []
for loop in re.finditer(r'for\s+v\s+in\s+(.*?);\s*do', body, re.S):
    names += re.findall(r'[A-Z][A-Z0-9_]+', loop.group(1).replace('\\\n', ' '))
names += re.findall(r"printf\s+'([A-Z][A-Z0-9_]+)=", body)
print('\n'.join(sorted(set(names))))
PY
)"
[[ -n "$WRITTEN" ]] || { fail "no variable could be derived from config_wizard's write block — the check lost its subject and is NOT reporting that as a pass"; return; }

DOCUMENTED="$(grep -oE '^[A-Z][A-Z0-9_]*=' "$CONF" | tr -d '=' | sort -u)"
MISSING=""; STALE=""
for v in $WRITTEN;    do grep -q "^$v=" "$CONF"        || MISSING="$MISSING $v"; done
for v in $DOCUMENTED; do grep -qx "$v"  <<<"$WRITTEN"  || STALE="$STALE $v";   done

printf "    %s variables derived from the wizard's write block\n" "$(wc -w <<<"$WRITTEN")"
if [[ -n "$MISSING" || -n "$STALE" ]]; then
    fail "conf.example and the wizard disagree —${MISSING:+ written by the wizard and undocumented:$MISSING}${STALE:+ documented but the wizard no longer writes it:$STALE}"
else
    pass "conf.example documents every variable the wizard writes, and none it does not"
fi
}
