# dientes del check 001 (bash -n de todos los scripts)
#
# Borrar un archivo no sirve como diente acá: el check contaría uno
# menos y seguiría verde. Lo único que prueba que este check MIDE es
# meterle sintaxis rota a un script de verdad.

# un `if` sin `fi` — el error más común al editar una fase a las 2 AM
red_1() {
    printf '\nif [[ -f /tmp/x ]]; then\n    echo hola\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"
}

# una comilla sin cerrar en una lib: bash -n lo ve, un grep no
red_2() {
    printf '\necho "esto no cierra\n' >> "$AEGIS_ROOT/lib/jenkins.sh"
}

# y en un comando, no solo en las fases: el alcance de v3 incluye
# libexec/ y lib/, que en v2 vivían en otro lado
red_3() {
    printf '\ncase x in\n' >> "$AEGIS_ROOT/libexec/aegis-rotate"
}

# control: un comentario nuevo no es un error de sintaxis
control_1() { printf '\n# comentario legitimo\n' >> "$AEGIS_ROOT/init/phases/20-k3s.sh"; }

# un módulo de librería —sin shebang, porque no es un comando— con la
# sintaxis rota. Hasta el 2026-08-24 este diente NO habría mordido: el
# lenguaje salía solo del shebang, y los seis módulos de lib/aegis/ se
# chequeaban por casualidad, según si su docstring mencionaba la
# palabra «python». 5.800 renglones cubiertos por azar.
red_4() {
    printf '\ndef roto(:\n' >> "$AEGIS_ROOT/lib/aegis/markers.py"
}
