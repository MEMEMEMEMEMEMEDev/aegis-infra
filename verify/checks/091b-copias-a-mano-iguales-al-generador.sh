# titulo: las copias a mano de los middlewares son byte a byte lo que emite el generador
# origen: verify-static.sh (v2) ══ 91, parte (b) — partida en v3
check() {
# El canario no tiene contrato (es lo que prueba que el camino del
# inquilino funciona, así que no puede depender de ese camino), pero
# necesita los tres middlewares igual. Están escritos A MANO en su
# ruteo.yaml, y tienen que ser byte a byte los que `aegis org` genera
# para cualquier organización con contrato: si alguien toca el
# generador y se olvida de la copia, el canario queda con la
# protección vieja y nadie se entera.
#
# En v2 la referencia era `org-blog`: una organización REAL de la
# instancia, committeada en platform/k8s/organizations/. Dos problemas
# que solo se ven desde v3: el artefacto no tiene org-blog (ni tiene
# por qué — la semilla no lleva instancia adentro, check 86), y una
# referencia atada a un nombre concreto miente el día que esa
# organización se borra. La referencia correcta no es otra copia: es
# EL GENERADOR.
#
# VERIFICAR (2026-08-23, T-02): conectar con `from aegis import
# derivar` y comparar contra render_ruteo() de verdad. Hasta que el
# paquete exista, esto NO SE PUDO EVALUAR — y lo dice, que es
# distinto de pasar en verde sin haber medido nada.
if python3 -c 'import sys; sys.path.insert(0, "'"$AEGIS_ROOT"'/lib"); import aegis.derivar' 2>/dev/null; then
    fail "existe lib/aegis/derivar.py pero este check todavía no lo usa — se prometió para T-02 y la promesa venció"
else
    skip "sin lib/aegis/derivar.py no hay generador contra el cual comparar (T-02); la referencia por nombre de organización se retiró a propósito"
fi
}
