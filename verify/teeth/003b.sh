# dientes del check 003b (el guard de plantillas reconoce lo que busca)
#
# El defecto que este check impide: el guard de `aegis app` deja pasar
# un placeholder sin rellenar y el operador recibe el repo de su app
# con __ROOT_DOMAIN__ escrito adentro, como literal.

# el patrón exacto que tenía el producto hasta el 2026-08-24: no
# reconoce ningún placeholder con guion bajo adentro.
rojo_1() {
    sed -i 's|^PLACEHOLDER = re.compile(r"__\[A-Z0-9_\]+__")|PLACEHOLDER = re.compile(r"__[A-Z]+__")|' \
        "$AEGIS_ROOT/libexec/aegis-app"
}

# un patrón que exige minúsculas: no reconoce NADA de lo que la semilla
# usa. Si el check solo mirase el patrón de reojo, este pasaría.
rojo_2() {
    sed -i 's|^PLACEHOLDER = re.compile(r"__\[A-Z0-9_\]+__")|PLACEHOLDER = re.compile(r"__[a-z]+__")|' \
        "$AEGIS_ROOT/libexec/aegis-app"
}

# control: una reescritura equivalente del patrón (mismo lenguaje,
# otro orden de la clase) NO puede ponerlo rojo — si lo hace, el check
# está comparando texto en vez de ejercer el guard.
control_1() {
    sed -i 's|^PLACEHOLDER = re.compile(r"__\[A-Z0-9_\]+__")|PLACEHOLDER = re.compile(r"__[_0-9A-Z]+__")|' \
        "$AEGIS_ROOT/libexec/aegis-app"
}
