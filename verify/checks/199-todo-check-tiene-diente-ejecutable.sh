# titulo: META — todo check tiene un diente ejecutable
# origen: V-199 (06 §1) — nuevo en v3
check() {
# La lección más cara del verificador de v2: «19 mutaciones, 19 bien
# clasificadas» era verdad el día que se escribió y nunca más. Los
# dientes se probaban a mano una vez y se olvidaban, y tres veces
# resultó que el diente mordía al propio check en vez del artefacto.
#
# Un check sin diente es una promesa sin prueba: puede estar midiendo
# el aire (sujeto vacío, ruta que ya no existe, patrón que nunca
# aparece) y pasar en verde para siempre. Este meta-check exige que
# cada uno tenga su archivo de dientes.
#
# La ALLOWLIST (teeth/PENDIENTES) existe porque portar 104 dientes no
# se hace de una sentada, y una regla que no se puede cumplir hoy se
# desactiva sola. Pero tiene dos candados: no puede nombrar checks que
# no existen, y no puede nombrar checks que YA tienen diente — si no,
# el día que alguien agrega un check y lo mete ahí «por ahora», nadie
# se entera. Y el número tiene que bajar: v3.0 no sale con la lista
# poblada (09 M-20).
D199=""
PEND="$AEGIS_ROOT/verify/teeth/PENDIENTES"
declare -A pendientes=()
if [[ -f "$PEND" ]]; then
    while read -r n _; do
        [[ -z "$n" || "$n" == \#* ]] && continue
        pendientes["$n"]=1
    done < "$PEND"
fi
sin_diente=() ; con_diente=0
for c in "$AEGIS_ROOT"/verify/checks/[0-9][0-9][0-9]*.sh; do
    b="$(basename "$c")"; n="${b%%-*}"
    if [[ -f "$AEGIS_ROOT/verify/teeth/$n.sh" ]]; then
        con_diente=$((con_diente+1))
        [[ -n "${pendientes[$n]:-}" ]] && D199="$D199 $n está en PENDIENTES pero YA tiene diente (la lista tapa huecos nuevos);"
        unset 'pendientes[$n]'
    else
        [[ -n "${pendientes[$n]:-}" ]] && { unset 'pendientes[$n]'; continue; }
        sin_diente+=("$n")
    fi
done
[[ ${#sin_diente[@]} -eq 0 ]] \
    || D199="$D199 sin diente y sin estar declarados en PENDIENTES: ${sin_diente[*]};"
[[ ${#pendientes[@]} -eq 0 ]] \
    || D199="$D199 PENDIENTES nombra checks que no existen: ${!pendientes[*]};"
printf '    %s checks con diente · %s en la lista de deuda (tiene que llegar a 0 antes de v3.0)\n' \
    "$con_diente" "$(grep -cvE '^\s*(#|$)' "$PEND" 2>/dev/null || echo 0)"
if [[ -n "$D199" ]]; then fail "dientes:$D199"
else pass "todo check tiene diente ejecutable o está en la lista de deuda, y la lista no miente"; fi
}
