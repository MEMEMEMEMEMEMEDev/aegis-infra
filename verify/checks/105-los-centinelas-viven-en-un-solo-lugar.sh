# titulo: los centinelas los escribe y los reconoce el mismo módulo
# origen: V-105 (03 §5.6) — nuevo en v3
check() {
# Clase B del registro, tres casos. El más caro: el banner «GENERADO
# POR `aegis org`» estaba escrito ocho veces como literal, y el guardia
# que decide si un archivo derivado fue editado a mano lo buscaba con
# un `in`. Cambiar la redacción en el productor y no en el guardia no
# rompe nada visible: el guardia deja de reconocer sus propios
# archivos y las ediciones a mano se pisan en silencio.
#
# La regla: si dos partes tienen que reconocer la misma cadena, la
# cadena vive UNA vez y las dos la importan.
D105=""
M="$LIBS/aegis/markers.py"
[[ -f "$M" ]] || { fail "no existe lib/aegis/markers.py — los centinelas no tienen dueño"; return; }
# Nadie más puede escribir estas cadenas a mano.
for centinela in 'GENERADO POR `aegis org`' '--- DERIVADO por aegis-org' '# hash: sha256:'; do
    # -I: un centinela es TEXTO. Sin esto el barrido matchea dentro de
    # un .pyc y denuncia una «copia a mano» que nadie escribió.
    COPIAS="$(grep -rlIF "$centinela" "$LIBS" "$LIBEXEC" 2>/dev/null | grep -v '/markers.py$' || true)"
    [[ -z "$COPIAS" ]] \
        || D105="$D105 '$centinela' escrito a mano fuera de markers.py: $(echo "$COPIAS" | tr '\n' ' ');"
done
# y el que RECONOCE tiene que usar el mismo módulo que el que escribe
grep -q 'markers.es_generado' "$LIBS/aegis/org.py" 2>/dev/null \
    || D105="$D105 el guardia de «editado a mano» no usa markers.es_generado;"
if [[ -n "$D105" ]]; then fail "centinelas:$D105"
else pass "los centinelas viven en lib/aegis/markers.py y los usan tanto el que escribe como el que reconoce"; fi
}
