# title: todo comando declara su metadata y el menú lo lista
# origen: V-101 (03 §2) — nuevo en v3
check() {
# La sección «Cobertura ausente» del registro con su número: de 12
# comandos, 1 tenía a alguien que lo verificara. Un comando que existe
# pero no aparece en el menú es un comando que nadie encuentra; uno que
# aparece pero no se puede ejecutar es peor, porque promete.
#
# El menú se DERIVA de estas dos líneas, así que no hay lista que
# mantener — pero eso solo funciona si están. Acá se exige.
D101=""
NL=0
for f in "$LIBEXEC"/aegis-*; do
    [[ -f "$f" ]] || continue
    b="$(basename "$f")"
    [[ -x "$f" ]] || D101="$D101 $b no es ejecutable;"
    S="$(sed -n '1,20{s/^# aegis-summary:[[:space:]]*//p}' "$f" | head -1)"
    G="$(sed -n '1,20{s/^# aegis-group:[[:space:]]*//p}'   "$f" | head -1)"
    [[ -n "$S" ]] || D101="$D101 $b sin aegis-summary;"
    case "$G" in
        setup|apps|operate|infra|backup|dev) ;;
        "") D101="$D101 $b sin aegis-group;" ;;
        *)  D101="$D101 $b declara un grupo que el menú no conoce ('$G');" ;;
    esac
    # y el resumen tiene que servir de resumen: una línea, sin punto
    # final, que quepa al lado del nombre.
    [[ ${#S} -le 75 ]] || D101="$D101 $b: el resumen no entra en el menú (${#S} caracteres);"
    NL=$((NL+1))
done
# el otro lado: lo que el menú muestra tiene que existir de verdad.
# (Se corre el despachador: es la única forma de probar que el menú
# derivado y los archivos coinciden — mirar el código no alcanza.)
while read -r n; do
    [[ -x "$LIBEXEC/aegis-$n" ]] || D101="$D101 el menú lista '$n' pero no hay libexec/aegis-$n ejecutable;"
done < <("$AEGIS_ROOT/bin/aegis" 2>/dev/null | sed -n 's/^  \([a-z][a-z-]*\) .*/\1/p')
printf '    %s comandos con metadata\n' "$NL"
if [[ -n "$D101" ]]; then fail "metadata de comandos:$D101"
else pass "los $NL comandos declaran summary y group, son ejecutables, y el menú derivado coincide con el disco"; fi
}
