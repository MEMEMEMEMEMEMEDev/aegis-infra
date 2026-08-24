# dientes del check 086 (la semilla no lleva instancia horneada)
# Ya se fugó dos veces. Una instancia dentro del artefacto significa
# que la próxima instalación nace apuntando a la máquina de otro.
#
# El rojo va por el sub-check que SIEMPRE está activo (el dueño de
# repo literal). El de contrastar contra el conf de la máquina solo
# corre si hay instancia — y descubrir que en v3 ya no la encontraba
# fue mérito de este diente.
rojo_1() {
    printf '\n# el repo: git@github.com:ejemplo-org/ops-stack-v2.git\n' \
        >> "$AEGIS_ROOT/semilla/plataforma/edge.yaml"
}
# control: la forma CORRECTA de nombrar lo mismo en el artefacto
control_1() {
    printf '\n# el repo: git@github.com:__GH_OWNER__/__PLATFORM_REPO__.git\n' \
        >> "$AEGIS_ROOT/semilla/plataforma/edge.yaml"
}
