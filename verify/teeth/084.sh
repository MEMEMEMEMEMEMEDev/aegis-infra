# dientes del check 084 (todo destino de escritura sobrevive a un clone)
#
# El generador automático había elegido «borrar .git/index» como
# mutación: el check se ponía rojo, sí, pero por haberle roto git al
# árbol, no por el defecto que vigila. Un diente que muerde por la
# razón equivocada es peor que no tener diente, porque da confianza.
#
# El defecto real: una fase escribe en un directorio de platform/ que
# la semilla no trae, así que en una máquina nueva —donde platform/
# nace de un clone de la semilla— esa escritura falla.
rojo_1() {
    printf '\ncp x "$PLATFORM_DIR/k8s/base/carpeta-que-la-semilla-no-trae/archivo.yaml"\n' \
        >> "$AEGIS_ROOT/init/phases/85-observabilidad.sh"
}
