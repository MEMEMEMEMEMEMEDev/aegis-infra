# dientes del check 105 (los centinelas viven en un solo lugar)
# Clase B: el banner estaba escrito ocho veces y el guardia lo buscaba
# con un `in`. Cambiarlo en un lado y no en el otro deja al guardia sin
# reconocer sus propios archivos, y las ediciones a mano se pisan.
rojo_1() {
    printf '\nOTRA_COPIA = "# ║  GENERADO POR `aegis org` — NO EDITAR A MANO ║"\n' \
        >> "$AEGIS_ROOT/lib/aegis/org.py"
}
rojo_2() { sed -i 's/markers\.es_generado(viejo)/"GENERADO POR `aegis org`" in viejo/' "$AEGIS_ROOT/lib/aegis/org.py"; }
