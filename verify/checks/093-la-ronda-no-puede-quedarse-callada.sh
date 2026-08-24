# titulo: la ronda no puede quedarse callada (los tres silencios)
# origen: verify-static.sh (v2) ══ 93
check() {
# La Enfermedad E tiene una forma peor que el verde falso: el RENGLÓN
# QUE FALTA. Un chequeo que informa salud sin medir al menos se puede
# discutir; uno que no informa nada no lo cuenta nadie, y la línea final
# —«sin fallos, N avisos»— sale igual de tranquila.
#
# Los tres silencios encontrados en bin/aegis-chequeo el 2026-08-22, que
# son las tres formas en que esto pasa:
#
#   1. el DESPACHO copiado. Los medidores grandes devuelven líneas con
#      su propio veredicto (MAL:/BIEN:/NOTA:/NO EVALUADO) y bash las
#      reparte. El reparto estaba escrito dos veces y las dos con el
#      mismo agujero: si el medidor revienta, el traceback se va a
#      stderr, la salida queda vacía, ninguna rama del case matchea y
#      la sección imprime su título y NADA MÁS.
#      El arreglo no fue tapar los dos: fue que el protocolo exista UNA
#      vez, en `despachar`, con el guard adentro. Este check mantiene
#      esa unicidad — una segunda copia es una segunda oportunidad de
#      equivocarse igual.
#
#   2. el `sys.exit(0)` dentro de un `except`. Salir CON BIEN desde el
#      manejador de un error es siempre mentira: la salida vacía se lee
#      idéntica a «medí y no encontré nada». Era el caso del medidor de
#      reinicios: si el JSON de kubectl no parseaba, la ronda decía «los
#      52 pods corren, ninguno reiniciando» sin haber mirado uno.
#      (Un `continue` dentro de un bucle sí puede ser legítimo —saltear
#      un ítem que no aplica— así que la regla es sobre el exit, que no
#      lo es nunca.)
#
#   3. la degradación en gris. `nota()` no cuenta nada, y eso está bien
#      cuando cuelga de un mal/aviso ya contado. Cuando es lo ÚNICO que
#      reporta que la medición se debilitó, el veredicto final no se
#      entera. Para eso está `degradado()`, que imprime igual de
#      discreto y suma un aviso; este check exige que exista y que la
#      diferencia entre las dos siga siendo real.
D93=""
CHQ="$LIBEXEC/aegis-chequeo"
if [[ ! -f "$CHQ" ]]; then
    D93="$D93 no existe bin/aegis-chequeo en la semilla (la ronda no viaja);"
else
    # 1) el protocolo, en un solo lugar.
    N_CASE="$(grep -c 'MAL:\*)' "$CHQ" || true)"
    [[ "$N_CASE" == "1" ]] \
        || D93="$D93 hay $N_CASE despachos de líneas MAL:/BIEN: (debe haber UNO, dentro de despachar): una copia del protocolo es una copia del agujero;"
    grep -q '^despachar() {' "$CHQ" \
        || D93="$D93 falta la función despachar: sin ella cada medidor grande vuelve a repartir sus líneas a mano;"
    # y el guard que la hace valer: sin la rama de «no dijo nada»,
    # despachar es el mismo case de antes con otro nombre.
    # Se busca la CONDICIÓN, no la palabra: `grep dijo` pasaba en verde
    # con el guard neutralizado a `true ||`, porque las asignaciones
    # `dijo=1` seguían ahí. Un check que se conforma con que el nombre
    # aparezca no mide el guard, mide la ortografía.
    sed -n '/^despachar() {/,/^}/p' "$CHQ" | grep -qE '\(\(\s*dijo\s*\)\)\s*\|\|\s*aviso' \
        || D93="$D93 despachar no lleva el guard «si no dijo nada, es un aviso» — sin esa línea es el case viejo con otro nombre;"
    # 2) salir con bien desde un manejador de error.
    MALOS93="$(python3 - "$CHQ" <<'PY'
import re, sys, pathlib
lineas = pathlib.Path(sys.argv[1]).read_text().splitlines()
malas = []
for n, l in enumerate(lineas):
    if not re.match(r"\s*except\b.*:\s*$", l):
        continue
    sangria = len(l) - len(l.lstrip())
    # el cuerpo del handler: las líneas más indentadas que el `except`
    for m in lineas[n + 1:]:
        if not m.strip():
            continue
        if len(m) - len(m.lstrip()) <= sangria:
            break
        if re.match(r"\s*sys\.exit\(0\)", m):
            malas.append(f"línea {n + 1}: {l.strip()} … {m.strip()}")
        if m.strip().startswith(("print", "sys.exit")):
            break
print("\x1e".join(malas))
PY
)"
    [[ -z "$MALOS93" ]] \
        || D93="$D93 manejador(es) de error que salen CON BIEN y en silencio [$(printf '%s' "$MALOS93" | tr '\036' ';')] — la salida vacía se lee igual que «medí y no había nada»;"
    # 3) la degradación cuenta.
    grep -q '^degradado() {.*avisos=' "$CHQ" \
        || D93="$D93 falta degradado() (o dejó de sumar avisos): una medición debilitada volvería a reportarse solo en gris;"
    # Y que se USE. Un helper que nadie llama es un helper revertido: la
    # degradación volvió a ser una nota gris y el archivo sigue teniendo
    # la función como coartada. Si algún día ninguna medición se degrada,
    # lo correcto es borrar degradado(), no dejarlo muerto — misma regla
    # que las exclusiones de aegis-semilla.
    N_DEG="$(grep -cE '^\s*degradado ' "$CHQ" || true)"
    [[ "$N_DEG" -ge 1 ]] \
        || D93="$D93 degradado() existe y no lo llama nadie: o la degradación volvió a reportarse en gris, o la función sobra;"
    grep -qE '^nota\(\)\s+\{[^}]*avisos=' "$CHQ" \
        && D93="$D93 nota() empezó a contar avisos: entonces ya no sirve como línea de detalle de un mal/aviso y todo detalle infla el recuento;"
fi
if [[ -n "$D93" ]]; then fail "la ronda puede quedarse callada:$D93"
else pass "la ronda no tiene forma de callarse: un solo despacho con su guard, ningún except que salga con bien, y la degradación cuenta ($N_DEG uso(s)) mientras nota() sigue sin contar"; fi
}
