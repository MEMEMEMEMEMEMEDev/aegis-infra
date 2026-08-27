# title: the wizard writes where nothing exists yet, and checks the write
# origin: new in v3 — 2026-08-27, the first init on a clean machine: "config written" over a failed mv
check() {
# On a clean machine the config is the first thing ever written under
# the instance's directory, and that directory does not exist yet. The
# first VPS run showed the whole chain of silence: `mv` failed (no
# such directory), `log_ok "config written"` printed anyway, and the
# init went on with the answers in memory — because config_wizard runs
# inside `|| die`, where bash suspends `set -e`. Then config_validate
# `source`d a file that was not there, printed bash's error, and the
# run walked past it. Three things are nailed here: the wizard creates
# the directory, the write is checked with its own `|| die`, and
# config_validate says "no config" instead of sourcing thin air.
D142=""
CS="$LIBS/config.sh"
W="$(body_of config_wizard "$CS")"
if [[ -z "$W" ]]; then
    D142="$D142 lib/config.sh has no config_wizard;"
else
    echo "$W" | grep -q 'mkdir -p "$(dirname "$CONF_FILE")"' \
        || D142="$D142 config_wizard does not create the config's directory before writing (the instance dir does not exist on a clean machine);"
    # the mv and its `|| die` may sit on one line or on the next
    echo "$W" | tr '\n' ' ' | grep -qE 'mv "\$tmp" "\$CONF_FILE" *(\\ )? *\|\| *\{[^}]*die' \
        || D142="$D142 the mv of the config is not followed by its own || die (inside config_wizard || die, set -e is suspended: a failed write is followed by 'config written');"
fi
V="$(body_of config_validate "$CS")"
if [[ -z "$V" ]]; then
    D142="$D142 lib/config.sh has no config_validate;"
else
    echo "$V" | grep -q '\[\[ -f "$CONF_FILE" \]\] ||' \
        || D142="$D142 config_validate sources \$CONF_FILE without checking it exists (bash's error scrolls past and the run continues);"
fi
if [[ -n "$D142" ]]; then fail "wizard write:$D142"
else pass "the wizard creates the instance dir, dies if the config cannot be written, and an absent config is said out loud"; fi
}
