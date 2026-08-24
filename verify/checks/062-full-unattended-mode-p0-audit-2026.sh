# title: full UNATTENDED mode (P0 audit 2026-07-18)
# origin: verify-static.sh (v2) ══ 62
check() {
# the design assumed an operator was present: 9+ prompts with no
# bypass, a wizard with an infinite busy-loop when stdin was closed,
# secrets only through a prompt.
D62=""
nc "$LIBEXEC/aegis-init" | grep -q -- '--non-interactive)' \
    || D62="$D62 aegis-init.sh without a --non-interactive flag;"
nc "$LIBEXEC/aegis-init" | grep -q -- '! -t 0' \
    || D62="$D62 no early TTY guard (with no terminal it died at the first read, minutes down the road);"
HS62="$(body_of human_step "$LIBS/common.sh")"
echo "$HS62" | grep -q 'ni_mode' || D62="$D62 human_step does not honour unattended mode;"
GR62="$(body_of gate_red "$LIBS/common.sh")"
echo "$GR62" | grep -q 'ni_mode' || D62="$D62 gate_red does not honour unattended mode;"
ASK62="$(body_of ask "$LIBS/config.sh")"
echo "$ASK62" | grep -q 'stdin closed' \
    || D62="$D62 ask() without an EOF cut-off (infinite busy-loop with stdin closed);"
echo "$ASK62" | grep -q 'tries' \
    || D62="$D62 ask() without a cap on invalid attempts;"
nc "$LIBS/config.sh" | grep -q 'ni_mode && die' \
    || D62="$D62 ensure_config does not demand a pre-made conf when unattended;"
nc "$PHASES/15-third-parties.sh" | grep -q 'CF_MASTER_FILE' \
    || D62="$D62 phase 15 without a file path for the CF master key;"
nc "$LIBS/secrets.sh" | grep -q 'AEGIS_AGE_BACKUP_FILE' \
    || D62="$D62 the ceremony has no file path for the age backup;"
nc "$PHASES/12-workrepos.sh" | grep -q 'ni_mode && die' \
    || D62="$D62 a repo without a marker would auto-confirm when unattended (it would overwrite a real repo with push --force);"
ABS62="$(body_of ansible_become_setup "$LIBS/common.sh")"
echo "$ABS62" | grep -q 'ni_mode && die' \
    || D62="$D62 become without NOPASSWD would hang asking for a password when unattended;"
if [[ -n "$D62" ]]; then fail "unattended mode:$D62"
else pass "unattended end to end: flag+TTY guard, bounded wizard, secrets by file, RED with an exception for someone else's repos"; fi
}
