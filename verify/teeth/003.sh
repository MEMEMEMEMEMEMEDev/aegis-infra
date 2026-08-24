# dientes del check 003 (todo placeholder tiene dueño declarado)
#
# El defecto que este check impide: un __LO_QUE_SEA__ que nadie rellena
# viaja al cluster tal cual y aparece como un hostname literal
# "__ROOT_DOMAIN__" en producción.

# un placeholder huérfano en un manifiesto del artefacto
rojo_1() {
    printf '\n# __PLACEHOLDER_SIN_DUENO__\n' >> "$AEGIS_ROOT/semilla/plataforma/edge.yaml"
}

# y en un .tf, que es la otra extensión que el check barre
rojo_2() {
    printf '\n# __OTRO_HUERFANO__\n' >> "$AEGIS_ROOT/semilla/plataforma/tofu/modules/cloudflare-access/main.tf"
}

# control: un placeholder que SÍ tiene dueño no puede ponerlo rojo —
# si lo hace, el check no está leyendo la allowlist sino gritando por
# cualquier __X__, que es lo que lo volvería inútil.
control_1() {
    printf '\n# __ROOT_DOMAIN__\n' >> "$AEGIS_ROOT/semilla/plataforma/edge.yaml"
}
