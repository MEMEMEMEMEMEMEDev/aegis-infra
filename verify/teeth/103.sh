# dientes del check 103 (ningún mensaje nombra un comando literal)
# La Clase E: ~155 strings con el nombre de un comando a mano. El día
# que el comando se llama distinto, el operador teclea lo que le
# dijeron y no existe.
red_1() { printf '\nlog_info "corré aegis-check para ver el estado"\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
red_2() { printf '\necho "usá bin/aegis-sync para forzarlo"\n' >> "$AEGIS_ROOT/libexec/aegis-init"; }
# control: la forma DERIVADA no puede morder — si mordiera, la regla
# sería imposible de cumplir y el check se volvería ruido.
control_1() { printf '\nlog_info "corré ${AEGIS_CMD:-aegis} check para ver el estado"\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
# control: y la excepción declarada tampoco
control_2() { printf '\n# clase-E-ok: etiqueta de stream\nlog_info "source=aegis-init"\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
