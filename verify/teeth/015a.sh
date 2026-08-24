# dientes del check 015a (D11: sin gestor de secretos asumido)
rojo_1() { printf '\nlog_info "guardá esto en Bitwarden antes de seguir"\n' >> "$AEGIS_ROOT/init/phases/10-age-ceremony.sh"; }
# control: el check excluye el DIRECTORIO verify/, no un nombre de
# archivo — si volviera a excluir por nombre, esto lo pondría rojo.
control_1() { printf '\n# titulo: mención de Bitwarden en un check\ncheck() { pass "nada"; }\n' > "$AEGIS_ROOT/verify/checks/998-mencion-legitima.sh"; }
