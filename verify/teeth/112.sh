# teeth for check 112 (every invoked command and subcommand exists)
#
# The regression it watches is the one phase 85 carried for a day: an
# invocation whose command or subcommand does not exist, and that only
# runs during a real installation.

# a subcommand the command does not declare (the 85.6 case, `borde`)
red_1() { printf '\nrun_cmd ${AEGIS_CMD:-aegis} org borde\n' >> "$AEGIS_ROOT/init/phases/85-observability.sh"; }
# a command that does not exist at all
red_2() { printf '\n${AEGIS_CMD:-aegis} nonesuch\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
# the path form: the code no longer lives there
red_3() { printf '\nbash -c "cd $PLATFORM_DIR && bin/aegis-org apply"\n' >> "$AEGIS_ROOT/init/phases/85-observability.sh"; }
# control: a declared subcommand, in the derived form, is exactly what
# a phase is supposed to write
control_1() { printf '\nrun_cmd ${AEGIS_CMD:-aegis} org apply\n' >> "$AEGIS_ROOT/init/phases/85-observability.sh"; }
# control: a COMMENT telling the story of the old call is legitimate —
# this very check tells it in its own header
control_2() { printf '\n# history: this used to run bin/aegis-org borde\n' >> "$AEGIS_ROOT/init/phases/85-observability.sh"; }
# control: a backtick-quoted path in a docstring is a citation of
# history, not a call (aegis-edge and dev/seed both carry one)
control_3() { printf '\nx="""see `bin/aegis-org` in the v2 tree"""\n' >> "$AEGIS_ROOT/init/phases/85-observability.sh"; }
