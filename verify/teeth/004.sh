# dientes del check 004 — generados el 2026-08-23 y VERIFICADOS:
# cada rojo se aplicó sobre una copia del árbol y el check se puso rojo.

# el sujeto desaparece: si el check no lo nota, no lo estaba leyendo
red_1() { rm -f "$AEGIS_ROOT/init/phases/85-observability.sh"; }

# control: un cambio LEGÍTIMO no puede ponerlo rojo
control_1() { printf '# comentario legitimo\n' >> "$AEGIS_ROOT/init/phases/85-observability.sh"; }

# El diente de la SEGUNDA CATEGORÍA de productor, que hasta el
# 2026-08-24 no existía porque la categoría estaba muerta: el check
# buscaba el generador DENTRO de la semilla, donde en v3 ya no puede
# estar (el código vive en el producto, 02 §1). Con esa rama muerta,
# todo secreto derivado de contratos salía «sin productor» — y uno que
# de verdad no tuviera productor se habría perdido en ese ruido.
#
# Este rojo saca al generador de donde el check lo busca ahora. Si el
# check volviera a la forma vieja —«no está, entonces no aplica»—
# pasaría en verde. Eso es lo que no puede volver a pasar.
red_3() {
    mv "$AEGIS_ROOT/lib/aegis/org.py" "$AEGIS_ROOT/lib/aegis/org.py.escondido"
}

# control: documentar mejor una entry existente es el cambio más
# legítimo que hay sobre un generator, y no puede ponerse rojo.
#
# (La primera versión de este control AGREGABA una entry repetida y el
#  check la mordió con razón: una entry duplicada mata a kustomize con
#  «already registered id». El diente estaba mal, no el check.)
control_2() {
    sed -i 's|^  - secret-garage-credentials\.enc\.yaml$|  # su rotacion con el cluster arriba deja al nodo sin hablarse a si mismo\n  - secret-garage-credentials.enc.yaml|' \
        "$AEGIS_ROOT/seed/platform/k8s/base/garage-system/secret-generator.yaml"
}
