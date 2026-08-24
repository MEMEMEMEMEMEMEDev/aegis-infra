# dientes del check 091b (las copias a mano vs el generador)
#
# Este check está en NO SE PUDO EVALUAR a propósito: la referencia
# correcta es el generador, y hasta que exista lib/aegis/derivar.py no
# hay contra qué comparar. El diente prueba que la promesa tiene fecha
# de vencimiento: el día que el módulo aparezca, el check se pone rojo
# hasta que alguien lo conecte. Una deuda que se cobra sola.
red_1() {
    mkdir -p "$AEGIS_ROOT/lib/aegis"
    printf 'def render_ruteo(*a, **k):\n    raise NotImplementedError\n' \
        > "$AEGIS_ROOT/lib/aegis/derivar.py"
}
