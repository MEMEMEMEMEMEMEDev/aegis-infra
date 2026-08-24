# dientes del meta-check 199 (todo check tiene diente ejecutable)
#
# El 199 no mide el ARTEFACTO: mide al verificador. Su sujeto son los
# archivos de verify/, así que quitarle un comando al producto —lo que
# el diente generado hacía— no lo toca. Sus tres modos de fallo:
rojo_1() {
    # un check nuevo sin diente
    printf '# titulo: check sin diente\ncheck() { pass "nada"; }\n' \
        > "$AEGIS_ROOT/verify/checks/997-sin-diente.sh"
}
rojo_2() {
    # la lista de deuda nombrando un check que no existe (una allowlist
    # que envejece es una allowlist que tapa huecos nuevos)
    printf '998\n' > "$AEGIS_ROOT/verify/teeth/PENDIENTES"
}
rojo_3() {
    # y la lista nombrando uno que SÍ tiene diente: si eso no fuera
    # rojo, alguien podría meter ahí un check y desactivarlo sin que
    # nada avise
    printf '001\n' > "$AEGIS_ROOT/verify/teeth/PENDIENTES"
}
# control: un check nuevo CON su diente no molesta a nadie
control_1() {
    printf '# titulo: check con diente\ncheck() { pass "nada"; }\n' \
        > "$AEGIS_ROOT/verify/checks/996-con-diente.sh"
    printf 'rojo_1() { :; }\n' > "$AEGIS_ROOT/verify/teeth/996.sh"
}
