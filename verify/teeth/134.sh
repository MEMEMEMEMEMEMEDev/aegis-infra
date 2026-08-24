# dientes del check 134 (la semilla es artefacto puro)
# La mitad de la deuda de v2 salía de tener el mismo código en dos
# lugares y una herramienta entera para vigilar que no se separaran.
rojo_1() {
    mkdir -p "$AEGIS_ROOT/semilla/plataforma/bin"
    printf '#!/usr/bin/env bash\necho hola\n' > "$AEGIS_ROOT/semilla/plataforma/bin/aegis-algo"
    chmod +x "$AEGIS_ROOT/semilla/plataforma/bin/aegis-algo"
}
rojo_2() {
    printf '#!/usr/bin/env bash\n' > "$AEGIS_ROOT/semilla/plataforma/k8s/script-colado.sh"
    chmod +x "$AEGIS_ROOT/semilla/plataforma/k8s/script-colado.sh"
}
