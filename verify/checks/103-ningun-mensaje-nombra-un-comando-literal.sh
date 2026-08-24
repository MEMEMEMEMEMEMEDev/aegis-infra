# title: ningún mensaje al operador escribe un nombre de comando a mano
# origen: V-103 (03 §1) — nuevo en v3
check() {
# La Clase E del registro: ~155 strings con el nombre de un comando
# escrito a mano. Cada uno es una promesa que envejece — el día que el
# comando se llama distinto, los mensajes siguen diciendo el nombre
# viejo, y el operador teclea lo que le dijeron y no existe. Peor: los
# COMENTARIOS de los manifiestos generados, que alguien lee meses
# después buscando cómo rehacer algo.
#
# La respuesta no es traducir 155 strings: es derivarlos de uno solo.
# $AEGIS_CMD (bash) y cli.cmd() (python) salen de argv[0].
#
# La lista de comandos se DERIVA de libexec/, no se escribe acá: el día
# que nazca un comando nuevo, esta regla lo cubre sin que nadie la
# toque. Y se exige que el nombre esté USADO COMO COMANDO (seguido de
# espacio, comilla o fin) — `aegis-init.conf` es un archivo,
# `aegis-ca.pem` es un certificado y `require-aegis-signature` es una
# policy: ninguno es un comando y ninguno debe morder.
#
# EXCEPCIÓN DECLARADA: `clase-E-ok:` con el motivo escrito, en la
# misma línea o en la de arriba (hay líneas que no admiten comentario
# al final, como las continuaciones con \).
# Se usa donde el nombre NO es un comando sino un dato (la etiqueta de
# un stream de logs, un topic de ntfy).
D103=""
mapfile -t CMDS < <(for f in "$LIBEXEC"/aegis-*; do [[ -f "$f" ]] && basename "$f"; done)
PAT="$(printf '%s|' "${CMDS[@]}" | sed 's/|$//')"
HITS="$(grep -rnE "(^|[[:space:]\"'\`(=])(bin/)?($PAT)([[:space:]\"'\`,;:)]|\\\\n|$)" \
        "$AEGIS_ROOT/libexec" "$LIBS" "$AEGIS_ROOT/init" "$AEGIS_ROOT/bin" 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    | grep -E '(printf|echo |print\(|log_(info|ok|warn|error)|die |morir\(|say )' \
    | grep -vE 'AEGIS_CMD|cli\.cmd|CMD_[A-Z]|clase-E-ok:' \
    | grep -vE '\$AEGIS_ROOT/libexec/|\$LIBEXEC/|libexec/state/|libexec/dev/' \
    || true)"
# La excepción también vale en la línea de ARRIBA: una continuación
# con \ no admite comentario al final, y obligar a reescribir el
# código para poder anotarlo sería el check mandando sobre el diseño.
HITS="$(printf '%s\n' "$HITS" | while IFS= read -r h; do
    [[ -z "$h" ]] && continue
    arch="${h%%:*}"; resto="${h#*:}"; num="${resto%%:*}"
    if [[ "$num" =~ ^[0-9]+$ ]] && (( num > 1 )) \
       && sed -n "$((num-1))p" "$arch" 2>/dev/null | grep -q 'clase-E-ok:'; then
        continue
    fi
    printf '%s\n' "$h"
done)"
N="$(printf '%s' "$HITS" | grep -c . || true)"
if [[ "$N" != 0 ]]; then
    printf '%s\n' "$HITS" | head -12 | sed 's/^/    /'
    D103=" $N mensajes escriben el nombre de un comando a mano (deben salir de \$AEGIS_CMD / cli.cmd());"
fi
printf '    %s comandos en la lista derivada de libexec/\n' "${#CMDS[@]}"
if [[ -n "$D103" ]]; then fail "Clase E:$D103"
else pass "ningún mensaje nombra un comando literal: todos se derivan de argv[0]"; fi
}
