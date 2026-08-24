# titulo: toda corrida del init deja expediente
# origen: verify-static.sh (v2) ══ 96
check() {
# Etapa C mínima (RUTA.md): hoy el stderr del init se pierde con la
# terminal. El wrapper aegis-init-log.sh captura la corrida ENTERA con
# script(1) —TTY vivo para el wizard, rc real— y la ruta del
# expediente se imprime ANTES de ejecutar: si la corrida muere, el
# operador ya sabe dónde leer. El log es evidencia local, no
# artefacto: gitignorado.
D96=""
ILOG="$LIBEXEC/aegis-init-log"
if [[ ! -f "$ILOG" ]]; then D96="$D96 falta libexec/aegis-init-log;"
else
    [[ -x "$ILOG" ]] || D96="$D96 no es ejecutable;"
    grep -q 'script -qefc' "$ILOG" \
        || D96="$D96 no usa script -qefc (sin -e el rc del init se pierde; sin script no hay TTY para el wizard);"
    L_EXP="$(grep -n "printf 'expediente:" "$ILOG" | head -1 | cut -d: -f1)"
    L_SCR="$(grep -n 'script -qefc' "$ILOG" | tail -1 | cut -d: -f1)"
    if [[ -z "$L_EXP" ]]; then D96="$D96 no imprime 'expediente:' (el operador no sabría dónde leer);"
    elif [[ -n "$L_SCR" && "$L_EXP" -gt "$L_SCR" ]]; then
        D96="$D96 la ruta del expediente se imprime DESPUÉS de correr: una corrida colgada no la muestra jamás;"
    fi
fi
# El expediente es estado de la INSTANCIA, no del producto. En v2
    # caía en init/.init-logs/ DENTRO del repo y hacía falta una línea
    # de .gitignore para que un `git add` distraído no versionara la
    # corrida entera con el stderr del host adentro. La regla de clase
    # es mejor que la exclusión: que no nazca donde no debe.
    grep -q 'AEGIS_STATE_DIR' "$ILOG" \
        || D96="$D96 el expediente no se escribe bajo \$AEGIS_STATE_DIR (si cae dentro del producto, un git add lo versiona con el stderr del host adentro);"
    nc "$ILOG" | grep -qE '\$AEGIS_ROOT/(init/)?\.init-log' \
        && D96="$D96 el expediente todavía se escribe dentro del producto;"
if [[ -n "$D96" ]]; then fail "96:$D96"
else pass "aegis-init-log: expediente por corrida, ruta primero, log fuera de git"; fi
}
