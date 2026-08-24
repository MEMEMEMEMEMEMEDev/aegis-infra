# titulo: todo script del producto y del artefacto parsea
# origen: verify-static.sh (v2) ══ 1
check() {
# En v2 esto barría `-name '*.sh'`, y en v2 alcanzaba: los comandos
# vivían en semilla/plataforma/bin/ y nadie los miraba tampoco, pero al
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
    case "$(head -c 200 "$f" | head -1)" in
        *bash*|*/sh|*" sh")
            if bash -n "$f" 2>/tmp/aegis-syn.err; then n_bash=$((n_bash+1))
            else D1="$D1 bash: $f: $(head -1 /tmp/aegis-syn.err);"; fi ;;
        *python*)
            if python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>/tmp/aegis-syn.err
            then n_py=$((n_py+1))
            else D1="$D1 python: $f: $(tail -1 /tmp/aegis-syn.err);"; fi ;;
    esac
done < <(find "$AEGIS_ROOT/init" "$LIBS" "$LIBEXEC" "$AEGIS_ROOT/verify" "$P" \
              -type f \( -name '*.sh' -o -name '*.py' -o -perm -u+x \) \
              -not -path '*/__pycache__/*')
# los archivos de checks y dientes no llevan shebang (los sourcea el
# runner), así que se validan aparte y con el mismo rasero.
while IFS= read -r f; do
    bash -n "$f" 2>/tmp/aegis-syn.err && n_bash=$((n_bash+1)) \
        || D1="$D1 bash: $f: $(head -1 /tmp/aegis-syn.err);"
done < <(find "$AEGIS_ROOT/verify/checks" "$AEGIS_ROOT/verify/teeth" -name '*.sh' -type f)
rm -f /tmp/aegis-syn.err
printf '    %s bash · %s python\n' "$n_bash" "$n_py"
if [[ -n "$D1" ]]; then fail "sintaxis:$D1"
else pass "todo script parsea: $n_bash de bash, $n_py de python (lenguaje derivado del shebang, no de la extensión)"; fi
}
