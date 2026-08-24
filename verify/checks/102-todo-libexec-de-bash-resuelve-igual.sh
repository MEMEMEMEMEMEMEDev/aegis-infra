# titulo: todo comando de bash resuelve el producto igual y no inventa la instancia
# origen: V-102 (02 §1) — nuevo en v3
check() {
# En v2 cada comando calculaba su raíz desde su propio __file__: seis
# copias de la misma línea (aegis-org:32, aegis-app:96, aegis-edge:45,
# aegis-destroy:26, aegis-backup:21, aegis-restore:15). C1/C2 del
# registro las llaman «dependencias invisibles a un grep»: el día que
# el archivo cambia de profundidad, la línea sigue compilando y apunta
# a otro lado.
#
# En v3 hay un preámbulo canónico y un solo resolvedor. Dos reglas:
#  a) quien resuelve el PRODUCTO lo hace con readlink -f (la fase 05
#     instala /usr/local/bin/aegis como symlink: con dirname a secas,
#     AEGIS_ROOT sería /usr/local);
#  b) nadie decide dónde está la INSTANCIA por su cuenta — eso es de
#     lib/paths.sh.
#
# ALCANCE: los comandos de bash. Los de python siguen calculando su
# RAIZ desde __file__ hasta que exista lib/aegis/paths.py.
# VERIFICAR (2026-08-23, T-02): extender esta regla a los de python.
D102=""
# También los SUBCOMANDOS (libexec/state/*, libexec/dev/*): son
# comandos completos, se pueden invocar solos, y tienen exactamente el
# mismo problema con el symlink de la fase 05. El glob `aegis-*` los
# dejaba afuera — lo descubrió el diente, que le sacó el readlink a
# state/backup y el check ni se inmutó.
for f in "$LIBEXEC"/aegis-* "$LIBEXEC"/state/* "$LIBEXEC"/dev/*; do
    [[ -f "$f" ]] || continue
    b="${f#"$LIBEXEC/"}"
    head -1 "$f" | grep -q 'bash' || continue     # los de python, en T-02
    if grep -q 'AEGIS_ROOT' "$f"; then
        grep -q 'readlink -f' "$f" \
            || D102="$D102 $b resuelve el producto sin readlink -f (rompe con el symlink de la fase 05);"
    fi
    # la instancia no se inventa: ni $HOME/aegis a mano, ni platform/
    # colgado del producto.
    # $HOME/aegis EXACTO: $HOME/aegis-respaldos es otra cosa (el
    # resguardo va deliberadamente FUERA del árbol) y $HOME/
    # aegis-preflight.sh es la copia para una VM limpia. Un patrón que
    # no distingue muerde lo sano, y un check que grita por cosas sanas
    # se deja de leer.
    nc "$f" | grep -qE '\$HOME/aegis($|[/"'"'"'[:space:]])' \
        && D102="$D102 $b decide dónde está la instancia por su cuenta (eso es de lib/paths.sh);"
    nc "$f" | grep -q '\$AEGIS_ROOT/platform' \
        && D102="$D102 $b cuelga platform/ del PRODUCTO (la instancia es \$AEGIS_HOME);"
done
# y el resolvedor tiene que ser uno solo
DEFS="$(grep -rl '^aegis_home()' "$LIBS" "$LIBEXEC" 2>/dev/null | wc -l)"
[[ "$DEFS" == 1 ]] || D102="$D102 hay $DEFS definiciones de aegis_home() (tiene que haber exactamente una, en lib/paths.sh);"
if [[ -n "$D102" ]]; then fail "resolución de rutas:$D102"
else pass "los comandos de bash resuelven el producto con readlink -f y la instancia sale de lib/paths.sh"; fi
}
