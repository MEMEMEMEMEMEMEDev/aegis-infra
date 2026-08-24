# title: ninguna palabra retirada del glosario vuelve al código
# origen: nuevo en v3 — el renombrado ES->EN del 2026-08-24
check() {
# El trinquete de la conversión al inglés. Mover 34.600 renglones de
# idioma no es peligroso por lo que se traduce mal: es peligroso porque
# durante semanas conviven las dos formas, y basta un archivo nuevo
# escrito con la costumbre vieja para que el nombre retirado siga vivo
# —y entonces «un concepto, un nombre» deja de ser cierto sin que nada
# lo diga. Es la regla 3 del diseño de la CLI, que nació de los DIEZ
# conflictos mismo-concepto-dos-nombres que el registro de v2
# documenta: edge/borde, backup/respaldo, rotate/rotar,
# canary/canario, template/plantilla, tenant/organización.
#
# La lista NO se escribe acá: se DERIVA de docs/glossary.md §3, que es
# el documento que un humano lee. Una lista en el check y otra en el
# doc es exactamente el par que se desincroniza — y el día que se
# desincronizan, gana la que nadie lee.
#
# Se miran solo los renglones que NO son comentario. Un comentario, y
# un documento, PUEDEN nombrar una palabra retirada cuando están
# contando la historia: varios lo hacen, y esa narración es lo más
# valioso que tiene este código. Lo que no puede es quedar en el
# código.
GLOS="$AEGIS_ROOT/docs/glossary.md"
[[ -f "$GLOS" ]] || { skip "no existe docs/glossary.md: no hay lista de la que derivar"; return; }

RETIRADAS="$(sed -n '/^## 3\. /,/^## 3b\. /p' "$GLOS" \
             | sed -n 's/^| `\([^`]*\)` | .*/\1/p')"
[[ -n "$RETIRADAS" ]] || { skip "la tabla de §3 del glosario está vacía"; return; }

D111="" ; N111=0
while IFS= read -r palabra; do
    [[ -z "$palabra" ]] && continue
    N111=$((N111+1))
    # nc: sin comentarios de renglón completo, que es el idioma que ya
    # habla el resto del verificador (verify/lib.sh).
    # verify/teeth/ queda FUERA, y no por comodidad: un diente contiene
    # código roto a propósito —esa es literalmente su función— y varios
    # de ellos tienen que escribir la palabra retirada para reintroducir
    # la regresión que vigilan. Meterlos en el alcance haría que el
    # trinquete mordiera a los dientes que lo prueban a él. Lo descubrió
    # su propio diente, en la primera corrida.
    HITS="$(command grep -rIn --exclude-dir=.git --exclude-dir=teeth --exclude='*.md' -F -- "$palabra" \
                "$AEGIS_ROOT/bin" "$LIBS" "$LIBEXEC" "$AEGIS_ROOT/init" \
                "$AEGIS_ROOT/verify" "$AEGIS_ROOT/share" "$SEED" 2>/dev/null \
            | grep -vE ':[0-9]+:[[:space:]]*(#|//)' || true)"
    [[ -n "$HITS" ]] && D111="$D111 '$palabra' volvió al código: $(echo "$HITS" | head -3 | cut -d: -f1,2 | tr '\n' ' ');"
done <<< "$RETIRADAS"

printf '    %s palabras retiradas vigiladas\n' "$N111"
if [[ -n "$D111" ]]; then fail "el glosario dice que estas palabras se retiraron y siguen ahí:$D111"
else pass "ninguna de las $N111 palabras retiradas aparece en código (los comentarios pueden contar la historia)"; fi
}
