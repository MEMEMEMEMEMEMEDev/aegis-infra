# titulo: todo script del producto y del artefacto parsea
# origen: verify-static.sh (v2) ══ 1
check() {
# En v2 esto barría `-name '*.sh'`, y en v2 alcanzaba: los comandos
# vivían en seed/platform/bin/ y nadie los miraba tampoco, pero al
# menos las fases y las libs terminaban en .sh.
#
# En v3 los comandos son VERBOS y no llevan extensión (libexec/aegis-
# init, libexec/aegis-org…). Con el filtro por extensión, este check
# dejaba fuera los 20 comandos enteros — lo descubrió su propio diente:
# se le metió `case x in` sin cerrar a libexec/aegis-rotate y siguió
# verde. Es la clase «filtro por nombre que deja de morder cuando el
# archivo cambia de forma» (H7 del registro), la misma que obligó a que
# el check 15a excluya un DIRECTORIO y no un nombre de archivo.
#
# El lenguaje se DERIVA del shebang, que es el único lugar donde está
# escrito de verdad. Y se chequea cada uno con su propio parser: un
# comando de python roto no lo ve `bash -n`, y en v2 no lo veía nadie.
D1="" ; n_bash=0 ; n_py=0
while IFS= read -r f; do
    # DOS señales, en orden, y ninguna opcional.
    #
    # (1) El SHEBANG, que es donde el lenguaje está escrito de verdad —
    #     y shebang quiere decir que la línea EMPIEZA con `#!`. La
    #     versión anterior hacía `case` sobre la primera línea entera, y
    #     el 2026-08-24 un check nuevo titulado «el paquete de python
    #     carga de verdad» entró por la rama de python porque su TÍTULO
    #     contenía la palabra: se le pasó `ast.parse` a un archivo de
    #     bash y el 001 se puso rojo por un archivo sano.
    #
    # (2) La EXTENSIÓN, para lo que legítimamente no lleva shebang: los
    #     módulos de lib/aegis/ son librerías, no comandos, y no deben
    #     tenerlo. Exigir shebang los dejaba fuera del barrido — y al
    #     medirlo se vio algo peor: bajo la regla vieja se chequeaban
    #     por CASUALIDAD, según si su docstring mencionaba la palabra
    #     «python». Seis módulos, 5.800 renglones, cubiertos por azar.
    #
    # Y lo que no cae en ninguna de las dos se DENUNCIA. Un archivo
    # ejecutable que ningún parser puede reclamar no es un archivo
    # inocente: es uno que nadie está mirando.
    linea1="$(head -c 200 "$f" | head -1)"
    lang=""
    case "$linea1" in
        '#!'*bash*|'#!'*/sh|'#!'*" sh") lang=bash ;;
        '#!'*python*)                   lang=python ;;
        *) case "$f" in
               *.sh) lang=bash ;;
               *.py) lang=python ;;
           esac ;;
    esac
    case "$lang" in
        bash)
            if bash -n "$f" 2>/tmp/aegis-syn.err; then n_bash=$((n_bash+1))
            else D1="$D1 bash: $f: $(head -1 /tmp/aegis-syn.err);"; fi ;;
        python)
            if python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>/tmp/aegis-syn.err
            then n_py=$((n_py+1))
            else D1="$D1 python: $f: $(tail -1 /tmp/aegis-syn.err);"; fi ;;
        *)  D1="$D1 sin lenguaje derivable (ni shebang ni extensión): $f;" ;;
    esac
done < <(find "$AEGIS_ROOT/init" "$LIBS" "$LIBEXEC" "$AEGIS_ROOT/verify" "$P" \
              -type f \( -name '*.sh' -o -name '*.py' -o -perm -u+x \) \
              -not -path '*/__pycache__/*')
# Los checks y los dientes no llevan shebang —los sourcea el runner—
# pero sí llevan `.sh`, así que el barrido de arriba ya los toma por
# extensión. Hasta el 2026-08-24 tenían su propio bucle acá abajo, y
# desde que la extensión pasó a ser señal de pleno derecho ese bucle
# los contaba DOS VECES: 228 archivos duplicados en un total de 523.
# Chequear dos veces no rompe nada; un número que miente, sí.
rm -f /tmp/aegis-syn.err
printf '    %s bash · %s python\n' "$n_bash" "$n_py"
if [[ -n "$D1" ]]; then fail "sintaxis:$D1"
else pass "todo script parsea: $n_bash de bash, $n_py de python (lenguaje derivado del shebang; la extensión respalda a lo que legítimamente no lo lleva)"; fi
}
