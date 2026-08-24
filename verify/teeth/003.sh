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

# un huérfano en semilla/plantillas/, que hasta el 2026-08-24 este
# check no barría: de ahí nace el repo de cada app del operador.
rojo_3() {
    printf '\n// __HUERFANO_EN_PLANTILLA__\n' >> "$AEGIS_ROOT/semilla/plantillas/base/repos/app/main.go"
}

# un huérfano en un .md del artefacto: la ceguera por extensión.
rojo_4() {
    printf '\n<!-- __HUERFANO_SIN_EXTENSION__ -->\n' \
        >> "$AEGIS_ROOT/semilla/plataforma/docs/protocols/organizacion.md"
}

# control: un placeholder de clase-plantilla (dueño: aegis app) no
# puede ponerlo rojo — si lo hace, el check no derivó la clase.
control_2() {
    printf '\n// __ORG__\n' >> "$AEGIS_ROOT/semilla/plantillas/base/repos/app/main.go"
}
