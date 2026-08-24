# dientes del check 111 (el trinquete del glosario)
#
# El riesgo real no es que alguien reescriba `paths.py` como `rutas.py`
# a propósito: es que un archivo NUEVO nazca con la costumbre vieja y
# nadie lo note, porque el árbol todavía está medio en español y una
# palabra más no llama la atención.
rojo_1() {
    printf '\nRUTAS_VIEJAS = "lib/aegis/rutas.py"\n' >> "$AEGIS_ROOT/lib/aegis/paths.py"
}

# la misma vuelta por el lado del artefacto, que es donde más duele:
# un manifiesto que vuelve a nombrar el archivo con su nombre retirado.
rojo_2() {
    printf '\n# nada\nviejo: planes.yaml\n' \
        >> "$AEGIS_ROOT/seed/platform/k8s/bootstrap/appprojects.yaml"
}

# y el caso que prueba que la lista se DERIVA del documento y no está
# escrita en el check: agregar una palabra al glosario tiene que
# empezar a vigilarla de inmediato.
rojo_3() {
    sed -i 's|^| `dominio_raiz` | `root_domain` | contract and edge key |$|\0\n| `gris` | `gray` | |' \
        "$AEGIS_ROOT/docs/glossary.md" 2>/dev/null || \
    python3 - "$AEGIS_ROOT/docs/glossary.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
ancla = "| `equivalencia-org.sh` | `org-equivalence.sh` | |\n"
s = s.replace(ancla, ancla + "| `gris` | `gray` | |\n", 1)
open(p, "w").write(s)
PY
}

# control: contar la historia en un COMENTARIO nombrando una palabra
# retirada es legítimo, y es lo que hacen los checks 108 y 001. Si esto
# se pusiera rojo, el trinquete estaría borrando la memoria del repo.
control_1() {
    printf '\n# historia: esto antes se llamaba rutas.py y planes.yaml\n' \
        >> "$AEGIS_ROOT/lib/aegis/paths.py"
}
