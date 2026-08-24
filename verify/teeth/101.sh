# teeth for check 101 (every command declares its metadata)
# Without metadata the command does not appear in the menu: it exists
# and nobody finds it. In v2, 11 of 12 commands had nobody verifying them.
red_1() { sed -i '/^# aegis-summary:/d' "$AEGIS_ROOT/libexec/aegis-edge" 2>/dev/null || sed -i '/^# aegis-summary:/d' "$AEGIS_ROOT/libexec/aegis-edge"; }
red_2() { sed -i 's/^# aegis-group:.*/# aegis-group:   invented/' "$AEGIS_ROOT/libexec/aegis-init"; }
red_3() { chmod -x "$AEGIS_ROOT/libexec/aegis-init"; }
