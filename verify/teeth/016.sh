# dientes del check 016 (sops de cifrado siempre con --config o --age)
# Sin --age explícito, sops toma la clave de un .sops.yaml que puede no
# ser el que uno cree — y el archivo queda cifrado para otro.
rojo_1() { printf '\nsops -e /tmp/algo.yaml > /tmp/algo.enc.yaml\n' >> "$AEGIS_ROOT/lib/secrets.sh"; }
control_1() { printf '\nsops -e --age "$AGE_PUBLIC" /tmp/algo.yaml > /tmp/algo.enc.yaml\n' >> "$AEGIS_ROOT/lib/secrets.sh"; }
