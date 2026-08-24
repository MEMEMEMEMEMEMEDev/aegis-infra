# dientes del check 101 (todo comando declara su metadata)
# Sin metadata el comando no sale en el menú: existe y nadie lo
# encuentra. En v2, 11 de 12 comandos no los verificaba nadie.
red_1() { sed -i '/^# aegis-summary:/d' "$AEGIS_ROOT/libexec/aegis-edge" 2>/dev/null || sed -i '/^# aegis-summary:/d' "$AEGIS_ROOT/libexec/aegis-edge"; }
red_2() { sed -i 's/^# aegis-group:.*/# aegis-group:   inventado/' "$AEGIS_ROOT/libexec/aegis-init"; }
red_3() { chmod -x "$AEGIS_ROOT/libexec/aegis-init"; }
