# dientes del check 106 (los docs citan comandos que existen)
# H3: organizacion.md documentaba `aegis org rotar`, que no existe. El
# operador lo teclea, no pasa nada, y concluye que se equivocó él.
red_1() { printf '\nCorré `aegis org rotar` para rotar el material.\n' >> "$AEGIS_ROOT/docs/OPERAR.md"; }
red_2() { printf '\nY después:\n\n```bash\naegis inventado apply\n```\n' >> "$AEGIS_ROOT/docs/OPERAR.md"; }
# control: la prosa que NOMBRA a aegis sin invocarlo no es una cita
control_1() { printf '\naegis se encarga de mantener esto al día.\n' >> "$AEGIS_ROOT/docs/OPERAR.md"; }
