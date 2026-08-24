# dientes del check 017 (los archivos que las fases referencian existen)
# Clase bug 4: la fase corre media hora y muere en el último paso
# porque un archivo no estaba. Se detecta ANTES, leyendo el código.
#
# El primer rojo de este diente descubrió que la mitad del check había
# quedado muerta al renombrar $AEGIS_V2_ROOT: buscaba una variable que
# ya no existe, así que no tenía sujetos y pasaba en verde. Los dos
# rojos de abajo cubren las dos mitades.
rojo_1() {
    printf '\nansible-playbook ansible/playbooks/no-existe.yml\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"
}
rojo_2() {
    printf '\nsource "$AEGIS_ROOT/lib/no-existe.sh"\n' >> "$AEGIS_ROOT/init/phases/35-gitops.sh"
}
