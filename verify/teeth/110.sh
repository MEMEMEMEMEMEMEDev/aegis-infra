# dientes del check 110 (todo subsistema ausente está declarado)
#
# El riesgo real no es que falte AI: es que MAÑANA alguien saque otro
# subsistema y no escriba nada. El rojo principal simula exactamente
# eso — borrar el protocolo y dejar la ausencia muda.
rojo_1() { rm -f "$AEGIS_ROOT/seed/platform/docs/protocols/attach-ai-subsystem.md"; }

# vaciar la carpeta de protocolos entera: la misma ausencia por otro
# camino, para que el check no dependa de un nombre de archivo.
rojo_2() { rm -rf "$AEGIS_ROOT/seed/platform/docs/protocols"; }

# y el caso que importa de verdad: un subsistema NUEVO que se saca sin
# documentar. Si el check solo vigilara a AI, esto pasaría en verde.
rojo_3() {
    cat >> "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'


COLAS_K8S = os.path.join(RAIZ, "k8s", "base", "queue-system", "bundle.yaml")
PY
}

# control: escribir MÁS documentación no puede ponerlo rojo.
control_1() {
    printf '\n\n## Nota agregada\n\nAlgo mas sobre k8s/base/ai-system/ y su vuelta.\n' \
        >> "$AEGIS_ROOT/seed/platform/docs/protocols/attach-ai-subsystem.md"
}

# La otra dirección, que es la que envejece sin que nadie mire: una
# declaración que nombra algo que SÍ está. Mismo rasero que la política
# de exclusión de `aegis dev seed` — una regla podada por el tiempo deja
# de proteger sin avisar, y una mentira en el lugar donde se busca la
# verdad es peor que no tener nada escrito.
rojo_4() {
    printf '\n<!-- aegis-absent: k8s/base/garage-system -->\n' \
        >> "$AEGIS_ROOT/seed/platform/docs/protocols/attach-ai-subsystem.md"
}
