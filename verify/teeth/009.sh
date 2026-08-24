# dientes del check 009 ('|| true' solo donde es legítimo)
# NEGATIVO: el check exige AUSENCIA, así que el diente AGREGA el defecto.
red_1() { printf '\ntrue || true   # tragarse un error de verdad\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
control_1() { printf '\n# un comentario que menciona || true sin usarlo\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }
