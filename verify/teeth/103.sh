# teeth for check 103 (no message names a command literally)
# Class E: ~155 strings with a command's name written by hand. The day
# the command is called something else, the operator types what they
# were told and it does not exist.
red_1() { printf '\nlog_info "run aegis-check to see the state"\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
red_2() { printf '\necho "use bin/aegis-sync to force it"\n' >> "$AEGIS_ROOT/libexec/aegis-init"; }
# control: the DERIVED form must not bite — if it did, the rule would be
# impossible to satisfy and the check would become noise.
control_1() { printf '\nlog_info "run ${AEGIS_CMD:-aegis} check to see the state"\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
# control: and neither must the declared exception
control_2() { printf '\n# clase-E-ok: log stream label\nlog_info "source=aegis-init"\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
