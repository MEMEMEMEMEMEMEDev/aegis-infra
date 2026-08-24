# dientes del check 108 (el paquete de python CARGA, no solo parsea)
#
# La regresión real, con fecha: el 2026-08-24, renombrando al inglés,
# `rutas.py` pasó a `paths.py` y `cli.py` se quedó pidiendo el nombre
# viejo. El archivo parseaba, el check 001 lo daba por bueno, `aegis
# verify` daba TODO PASS, y `aegis org apply` moría en el import.
# red_1 ES esa regresión, no una parecida.
red_1() {
    sed -i 's/^from \. import paths$/from . import rutas/' "$AEGIS_ROOT/lib/aegis/cli.py"
}

# La otra mitad, y falla distinto: acá no se rompe quien importa, se
# muda quien es importado. El estático lo tiene que ver sin ejecutar
# nada — un módulo que no está no puede fallar «al cargarse».
red_2() {
    mv "$AEGIS_ROOT/lib/aegis/markers.py" "$AEGIS_ROOT/lib/aegis/centinelas.py"
}

# Y el caso que solo la carga REAL puede ver: sintaxis impecable,
# import interno muerto. `ast.parse` dice que sí; el intérprete, que no.
red_3() {
    printf '\nimport aegis.este_modulo_no_existe\n' >> "$AEGIS_ROOT/lib/aegis/outcomes.py"
}

# control: agregar un módulo nuevo al paquete y usarlo es exactamente
# lo que se espera que la gente haga. No puede ponerse rojo.
control_1() {
    cat > "$AEGIS_ROOT/lib/aegis/legitimo.py" <<'PY'
"""Un módulo nuevo, bien formado, como el que agregaría cualquiera."""
VALOR = 1
PY
    printf '\nfrom aegis import legitimo  # noqa: E402,F401\n' \
        >> "$AEGIS_ROOT/libexec/aegis-org"
}
