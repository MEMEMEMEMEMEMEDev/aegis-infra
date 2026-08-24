# dientes del check 014b (sin echo de UI a stdout en las libs)
# El defecto: el salto de línea tras `read -rsp` sale por stdout y
# contamina el valor que la función devuelve por $().
red_1() { printf '\n_ui_rota() { read -rsp "clave: " x; echo\n}\n' >> "$AEGIS_ROOT/lib/secrets.sh"; }
control_1() { printf '\n_ui_sana() { read -rsp "clave: " x; echo >&2\n}\n' >> "$AEGIS_ROOT/lib/secrets.sh"; }
