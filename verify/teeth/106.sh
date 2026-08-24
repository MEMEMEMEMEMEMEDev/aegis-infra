# teeth for check 106 (the docs cite commands that exist)
# H3: organizacion.md documented `aegis org rotar`, which does not
# exist. The operator types it, nothing happens, and concludes it was
# their own mistake.
red_1() { printf '\nRun `aegis org rotar` to rotate the key material.\n' >> "$AEGIS_ROOT/docs/OPERATE.md"; }
red_2() { printf '\nAnd then:\n\n```bash\naegis invented apply\n```\n' >> "$AEGIS_ROOT/docs/OPERATE.md"; }
# control: prose that NAMES aegis without invoking it is not a citation
control_1() { printf '\naegis takes care of keeping this up to date.\n' >> "$AEGIS_ROOT/docs/OPERATE.md"; }
