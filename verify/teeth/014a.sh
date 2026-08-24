# dientes del check 014a (log_* a stderr)
# El defecto real de la validación #1: un log que vuelve a stdout
# contamina toda función capturada con $().
red_1() { sed -i 's|^log_info()  { printf .*|log_info()  { printf "[INFO] %s\\n" "$*"; }|' "$AEGIS_ROOT/lib/common.sh"; }
control_1() { printf '\n# comentario legitimo sobre log_info\n' >> "$AEGIS_ROOT/lib/common.sh"; }
